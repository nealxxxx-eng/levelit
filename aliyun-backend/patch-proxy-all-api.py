#!/usr/bin/env python3
"""
把 levelit-proxy 的转发规则改成「catch-all」：任何 /api/ 开头、且未被本地 AI 端点
处理（/api/analyze、/api/estimate-daily-energy 在更靠前的分支已 return）的请求，
统统转发到本机 auth backend (127.0.0.1:3000)。

这样 /api/auth、/api/pk、/api/friends、/api/users、/api/leaderboard 以及未来新增的
所有端点都自动覆盖，无需每加一个端点就补一次代理。幂等。
"""
import subprocess, sys

res = subprocess.run(
    ["find", "/opt", "/home", "/root", "-name", "server.js", "-path", "*/levelit-proxy/*"],
    capture_output=True, text=True
)
cands = [p.strip() for p in res.stdout.splitlines() if p.strip()]
if not cands:
    print("❌ 找不到 levelit-proxy/server.js"); sys.exit(1)
path = cands[0]
print(f"找到: {path}")
txt = open(path).read()

CATCH_ALL = 'req.url && req.url.startsWith("/api/")'
candidates = [
    'req.url && (req.url.startsWith("/api/auth/") || req.url.startsWith("/api/pk/"))',
    'req.url && req.url.startsWith("/api/auth/")',
]

if CATCH_ALL in txt and not any(c in txt for c in candidates):
    print("✓ 已是 catch-all 转发，无需修改"); sys.exit(0)

replaced = False
for c in candidates:
    if c in txt:
        txt = txt.replace(c, CATCH_ALL, 1)
        replaced = True
        break

if not replaced:
    print("❌ 未找到预期的转发条件，请人工检查 proxy server.js"); sys.exit(1)

open(path, "w").write(txt)
print(f"✓ 已改为 catch-all /api/ 转发: {path}")

for svc in ["levelit-proxy", "levelit"]:
    r = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True)
    if r.returncode == 0:
        subprocess.run(["systemctl", "restart", svc])
        print(f"✓ 已重启 {svc}")
        break
else:
    print("⚠ 未找到 levelit-proxy 服务，请手动重启")
