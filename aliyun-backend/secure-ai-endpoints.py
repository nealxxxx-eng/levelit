#!/usr/bin/env python3
"""
给 levelit-proxy 的 AI 端点 (/api/analyze, /api/estimate-daily-energy) 加鉴权 (#2)。

方案：委托验证——proxy 不持有密钥，把 Bearer token 转发给本机
127.0.0.1:3000/api/auth/me 校验；200 即放行，否则 401。
单一密钥源，且顺带确认用户仍存在。幂等：重复运行不会重复注入。
"""
import subprocess
import sys

# ── 定位 proxy 的 server.js
res = subprocess.run(
    ["find", "/opt", "/home", "/root", "-name", "server.js", "-path", "*/levelit-proxy/*"],
    capture_output=True, text=True
)
candidates = [p.strip() for p in res.stdout.splitlines() if p.strip()]
if not candidates:
    print("❌ 找不到 levelit-proxy/server.js")
    sys.exit(1)
path = candidates[0]
print(f"找到: {path}")

txt = open(path).read()

if "verifyBearer" in txt:
    print("✓ 已打过鉴权补丁，跳过")
    sys.exit(0)

# ── 1. 注入 verifyBearer 辅助函数（在 createServer 之前）
helper = '''// #2：AI 端点鉴权——委托本机 auth backend 校验 token
function verifyBearer(req) {
  return new Promise((resolve) => {
    const auth = req.headers["authorization"] || "";
    if (!auth.startsWith("Bearer ")) return resolve(false);
    const r = http.request(
      { hostname: "127.0.0.1", port: 3000, path: "/api/auth/me", method: "GET",
        headers: { authorization: auth } },
      (resp) => { resp.resume(); resolve(resp.statusCode === 200); }
    );
    r.on("error", () => resolve(false));
    r.setTimeout(5000, () => { r.destroy(); resolve(false); });
    r.end();
  });
}

'''
marker = "const server = http.createServer"
if marker not in txt:
    print("❌ 未找到 createServer，proxy 结构与预期不符，请人工处理")
    sys.exit(1)
txt = txt.replace(marker, helper + marker, 1)

# ── 2. 在两个 AI 路由开头插入鉴权守卫
guard = '''    if (!(await verifyBearer(req))) {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "unauthorized" }));
      return;
    }
'''
routes = [
    'if (req.url === "/api/analyze" && req.method === "POST") {\n',
    'if (req.url === "/api/estimate-daily-energy" && req.method === "POST") {\n',
]
injected = 0
for route in routes:
    if route in txt:
        txt = txt.replace(route, route + guard, 1)
        injected += 1
    else:
        print(f"⚠ 未找到路由: {route.strip()}")

if injected == 0:
    print("❌ 两个 AI 路由都没找到，未做修改")
    sys.exit(1)

# ── 3. CORS 放行 Authorization 头（为将来 web 客户端，原生 App 不受影响）
txt = txt.replace(
    '"Access-Control-Allow-Headers", "Content-Type"',
    '"Access-Control-Allow-Headers", "Content-Type, Authorization"', 1
)

open(path, "w").write(txt)
print(f"✓ 已为 {injected} 个 AI 路由注入鉴权: {path}")

# ── 4. 重启 proxy
for svc in ["levelit-proxy", "levelit"]:
    r = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True)
    if r.returncode == 0:
        subprocess.run(["systemctl", "restart", svc])
        print(f"✓ 已重启 {svc}")
        break
else:
    print("⚠ 未找到 levelit-proxy 服务，请手动重启")
