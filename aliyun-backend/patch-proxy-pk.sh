#!/usr/bin/env bash
# 在 levelit-proxy 的 server.js 里补充 /api/pk/ 代理规则
# 用法: bash patch-proxy-pk.sh [服务器IP]
set -euo pipefail
SERVER="${1:-39.105.196.84}"
ssh-keyscan -H "$SERVER" >> ~/.ssh/known_hosts 2>/dev/null

ssh "root@$SERVER" python3 << 'PYEOF'
import subprocess, re, os

# 找 levelit-proxy server.js
result = subprocess.run(
    ["find", "/opt", "/home", "/root", "-name", "server.js", "-path", "*/levelit-proxy/*"],
    capture_output=True, text=True
)
candidates = [p.strip() for p in result.stdout.splitlines() if p.strip()]
if not candidates:
    result2 = subprocess.run(
        ["find", "/opt", "/home", "/root", "-name", "server.js"],
        capture_output=True, text=True
    )
    candidates = [p.strip() for p in result2.stdout.splitlines() if p.strip()]

if not candidates:
    print("❌ 找不到 server.js，请手动检查 levelit-proxy 路径")
    exit(1)

path = candidates[0]
print(f"找到文件: {path}")
txt = open(path).read()

# 已有 /api/pk/ 则跳过
if "/api/pk/" in txt:
    print("✓ /api/pk/ 代理规则已存在，无需修改")
    exit(0)

# 把 /api/auth/ 已有 proxy 段复制改为 /api/pk/
# 策略：在 /api/auth/ 代理块后面插入相同结构的 /api/pk/ 块
# 找到已有的 /api/auth/ 代理逻辑
new_block = txt.replace(
    "pathname.startsWith('/api/auth/')",
    "pathname.startsWith('/api/auth/') || pathname.startsWith('/api/pk/')"
)
if new_block == txt:
    print("⚠ 未找到 /api/auth/ 代理规则，请手动修改 levelit-proxy")
    exit(1)

open(path, "w").write(new_block)
print(f"✓ 已将 /api/pk/ 加入代理规则：{path}")

# 重启 levelit-proxy
for svc in ["levelit-proxy", "levelit"]:
    r = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True)
    if r.returncode == 0:
        subprocess.run(["systemctl", "restart", svc])
        print(f"✓ 已重启 {svc}")
        break
PYEOF

echo ""
echo "验证 /api/pk/ 代理..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer invalid" \
    "http://$SERVER/api/pk/challenges")
if [ "$HTTP" = "401" ]; then
    echo "✓ /api/pk/challenges 响应 401（代理正常，token 无效）"
else
    echo "⚠ /api/pk/challenges 返回 HTTP $HTTP（预期 401）"
fi
