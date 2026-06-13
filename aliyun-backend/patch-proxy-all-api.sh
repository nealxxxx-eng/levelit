#!/usr/bin/env bash
# 把 levelit-proxy 改成 catch-all /api/ 转发（覆盖 friends/users/leaderboard 及未来端点）。
# 用法: bash patch-proxy-all-api.sh [服务器IP]
set -euo pipefail
SERVER="${1:-39.105.196.84}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

scp "$SCRIPT_DIR/patch-proxy-all-api.py" "root@$SERVER:/tmp/patch-proxy-all-api.py"
ssh "root@$SERVER" "python3 /tmp/patch-proxy-all-api.py; rm -f /tmp/patch-proxy-all-api.py"

echo ""
echo "==> 验证（无 token 应 401，表示代理已转发到后端）"
for ep in friends "users/search?q=ab" leaderboard; do
  CODE=$(ssh "root@$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://localhost/api/$ep")
  echo "    /api/$ep -> HTTP $CODE (期望 401)"
done
