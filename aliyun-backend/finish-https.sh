#!/usr/bin/env bash
# 收尾：证书已签发安装，仅创建并启动 levelit-tls 服务（不重签证书）。
# 用法: bash finish-https.sh [服务器IP]
set -euo pipefail
SERVER="${1:-39.105.196.84}"

ssh "root@$SERVER" bash <<'ENDSSH'
set -euo pipefail

# 校验证书存在
[ -f /etc/levelit/tls/fullchain.pem ] && [ -f /etc/levelit/tls/privkey.pem ] || {
  echo "✗ 证书文件缺失 /etc/levelit/tls/，请先跑 setup-https.sh"; exit 1; }

NODE_BIN=$(command -v node || command -v nodejs)
cat > /etc/systemd/system/levelit-tls.service <<EOF
[Unit]
Description=LevelIt TLS terminator (8443 -> 127.0.0.1:80)
After=network.target

[Service]
Type=simple
ExecStart=$NODE_BIN /opt/levelit-tls/server.mjs
Environment=TLS_PORT=8443
Environment=UPSTREAM_PORT=80
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable levelit-tls
systemctl restart levelit-tls
sleep 1

command -v ufw >/dev/null 2>&1 && ufw allow 8443/tcp >/dev/null 2>&1 || true
command -v firewall-cmd >/dev/null 2>&1 && { firewall-cmd --add-port=8443/tcp --permanent >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1; } || true

if systemctl is-active --quiet levelit-tls; then
  echo "✓ levelit-tls 已启动"
  curl -sk -o /dev/null -w '  本机 HTTPS health: %{http_code}\n' https://localhost:8443/health
else
  echo "✗ 启动失败:"; journalctl -u levelit-tls -n 20 --no-pager; exit 1
fi
ENDSSH
