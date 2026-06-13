#!/usr/bin/env bash
# 用法: bash deploy-auth.sh [服务器IP]
# 需要: ssh, scp, openssl

set -euo pipefail

SERVER="${1:-39.105.196.84}"
REMOTE_DIR="/opt/levelit-auth"
DB_DIR="/var/lib/levelit"
ENV_FILE="/etc/levelit/auth.env"
SERVICE_NAME="levelit-auth"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 目标服务器: $SERVER"

# ── 信任主机指纹
echo "==> 获取服务器主机指纹..."
ssh-keyscan -H "$SERVER" >> ~/.ssh/known_hosts 2>/dev/null
echo "    指纹已写入 ~/.ssh/known_hosts"

# ── secret 在远端按需生成：已存在则复用，避免每次部署轮换密钥导致全员被登出
#    （#8）

# ── 上传源文件（server.js、package.json 以及 api/ 目录）
echo "==> 上传文件到 $SERVER:$REMOTE_DIR ..."
ssh "root@$SERVER" "mkdir -p $REMOTE_DIR/api"
scp "$SCRIPT_DIR/server.js" "$SCRIPT_DIR/package.json" "root@$SERVER:$REMOTE_DIR/"
scp "$SCRIPT_DIR/api/pk.js" "$SCRIPT_DIR/api/apns.js" \
    "$SCRIPT_DIR/api/social.js" "$SCRIPT_DIR/api/users-store.js" \
    "root@$SERVER:$REMOTE_DIR/api/"

# ── 远程配置
echo "==> 配置服务器..."
ssh "root@$SERVER" /bin/bash << ENDSSH
set -euo pipefail

# 1. 写 env 文件
mkdir -p /etc/levelit
# #8：复用已有 secret，没有才新生成。否则每次部署都会让所有 JWT 失效、用户被登出。
if [ -f "$ENV_FILE" ] && grep -q '^LEVELIT_AUTH_SECRET=' "$ENV_FILE"; then
    SECRET=\$(grep '^LEVELIT_AUTH_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2-)
    echo "    复用已有 AUTH_SECRET"
else
    SECRET=\$(openssl rand -hex 32)
    echo "    生成新的 AUTH_SECRET"
fi
cat > "$ENV_FILE" << EOF
LEVELIT_AUTH_SECRET=\$SECRET
LEVELIT_DB_FILE=$DB_DIR/users.json
LEVELIT_PK_DB_FILE=$DB_DIR/pk.json
LEVELIT_SOCIAL_DB_FILE=$DB_DIR/social.json
NODE_ENV=production
EOF
chmod 600 "$ENV_FILE"
echo "    env 文件已写入 $ENV_FILE"

# 2. 创建 DB 目录
mkdir -p "$DB_DIR"
chmod 700 "$DB_DIR"

# 3. 找可用的非 root 用户（找不到就用 root）
SVC_USER=\$(getent passwd | awk -F: '\$3>=1000 && \$3<65534 {print \$1; exit}')
SVC_USER=\${SVC_USER:-root}
NODE_BIN=\$(command -v node || command -v nodejs)
echo "    service 用户: \$SVC_USER  node: \$NODE_BIN"

# 4. 生成 systemd service
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=LevelIt Auth Backend
After=network.target

[Service]
Type=simple
User=\$SVC_USER
WorkingDirectory=$REMOTE_DIR
ExecStart=\$NODE_BIN server.js
EnvironmentFile=$ENV_FILE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. 启动服务
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 1
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "    ✓ 服务启动成功"
else
    echo "    ✗ 服务启动失败，日志:"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
    exit 1
fi

# 6. 找 nginx 配置文件
NGINX_CONF=\$(find /etc/nginx/sites-available /etc/nginx/conf.d -type f 2>/dev/null | head -1)
if [ -z "\$NGINX_CONF" ]; then
    NGINX_CONF="/etc/nginx/conf.d/levelit.conf"
    echo "server {" > "\$NGINX_CONF"
    echo "    listen 80;" >> "\$NGINX_CONF"
    echo "    server_name _;" >> "\$NGINX_CONF"
    echo "}" >> "\$NGINX_CONF"
    echo "    新建 nginx 配置: \$NGINX_CONF"
fi

# 7. 写入 /api/auth/ 代理块（幂等）
if grep -q "api/auth" "\$NGINX_CONF" 2>/dev/null; then
    echo "    ✓ Nginx 已有 /api/auth/ 配置，跳过"
else
    python3 - "\$NGINX_CONF" << 'PYEOF'
import sys, re
path = sys.argv[1]
txt = open(path).read()
block = """
    location /api/auth/ {
        proxy_pass         http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header   Host            \$host;
        proxy_set_header   X-Real-IP       \$remote_addr;
        proxy_read_timeout 35s;
    }
"""
# 在最后一个 } 前插入
idx = txt.rfind('}')
if idx == -1:
    txt += "\nserver {\n" + block + "\n}\n"
else:
    txt = txt[:idx] + block + txt[idx:]
open(path, 'w').write(txt)
print("    ✓ Nginx 配置已更新:", path)
PYEOF
    nginx -t && systemctl reload nginx && echo "    ✓ Nginx reload 成功" || {
        echo "    ✗ Nginx 配置有误，请手动检查 \$NGINX_CONF"
        exit 1
    }
fi

# 8. 验证
echo ""
echo "==> 部署完成！验证中..."
sleep 1
RESULT=\$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost/api/auth/register \
    -H 'Content-Type: application/json' \
    -d '{"identifier":"deploy-test@test.com","password":"testpass","profile":{"displayName":"测试","gender":"male","age":25,"heightCM":175,"weightKG":70,"activityLevel":"light"}}')
if [ "\$RESULT" = "201" ] || [ "\$RESULT" = "409" ]; then
    echo "    ✓ /api/auth/register 响应正常 (HTTP \$RESULT)"
else
    echo "    ✗ 验证失败，HTTP \$RESULT（可能 nginx 还需要手动检查）"
fi
ENDSSH

echo ""
echo "==> 全部完成。"
