#!/usr/bin/env bash
# 给 levelit-proxy 的 AI 端点加鉴权 (#2)。
# 用法: bash secure-ai-endpoints.sh [服务器IP]
set -euo pipefail
SERVER="${1:-39.105.196.84}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ssh-keyscan -H "$SERVER" >> ~/.ssh/known_hosts 2>/dev/null
echo "==> 上传补丁脚本..."
scp "$SCRIPT_DIR/secure-ai-endpoints.py" "root@$SERVER:/tmp/secure-ai-endpoints.py"
echo "==> 执行补丁..."
ssh "root@$SERVER" "python3 /tmp/secure-ai-endpoints.py; rm -f /tmp/secure-ai-endpoints.py"

echo ""
echo "==> 验证: 无 token 应返回 401"
HTTP_NOAUTH=$(ssh "root@$SERVER" "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://localhost/api/estimate-daily-energy")
echo "    无 token → HTTP $HTTP_NOAUTH (期望 401)"
