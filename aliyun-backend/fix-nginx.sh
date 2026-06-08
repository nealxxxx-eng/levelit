#!/usr/bin/env bash
# 把 /api/auth/ 代理插入 levelit-proxy server.js
# 用法: bash fix-nginx.sh [服务器IP]

set -euo pipefail
SERVER="${1:-39.105.196.84}"

ssh-keyscan -H "$SERVER" >> ~/.ssh/known_hosts 2>/dev/null
scp /tmp/patch-proxy.py "root@$SERVER:/tmp/patch-proxy.py"
echo "==> 执行补丁..."
ssh "root@$SERVER" "python3 /tmp/patch-proxy.py; rm -f /tmp/patch-proxy.py"
