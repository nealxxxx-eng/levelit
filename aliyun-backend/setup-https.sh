#!/usr/bin/env bash
# 配置 HTTPS：DuckDNS 子域名 + Let's Encrypt(DNS-01) + 8443 TLS 终结器。
#
# 用法:
#   DUCKDNS_TOKEN=你的token bash setup-https.sh [域名] [服务器IP]
#   例: DUCKDNS_TOKEN=abcd-1234 bash setup-https.sh levelit.duckdns.org 39.105.196.84
#
# 前置:
#   1) DuckDNS 子域名已指向该服务器 IP
#   2) 阿里云安全组已放行 8443 入站(本脚本无法操作云控制台,需你手动开)
set -euo pipefail

DOMAIN="${1:-levelit.duckdns.org}"
SERVER="${2:-39.105.196.84}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${DUCKDNS_TOKEN:?请设置 DUCKDNS_TOKEN 环境变量(DuckDNS 页面的 token)}"

# DuckDNS 的 dns_duckdns 插件需要 token 中的子域名前缀去掉 .duckdns.org
echo "==> 域名: $DOMAIN  服务器: $SERVER"

echo "==> 上传 TLS 终结器..."
ssh "root@$SERVER" "mkdir -p /opt/levelit-tls"
scp "$SCRIPT_DIR/levelit-tls.mjs" "root@$SERVER:/opt/levelit-tls/server.mjs"

echo "==> 远程配置(安装 acme.sh、签证书、起服务)..."
ssh "root@$SERVER" "DUCKDNS_TOKEN='$DUCKDNS_TOKEN' DOMAIN='$DOMAIN' bash -s" <<'ENDSSH'
set -euo pipefail

# 1. 安装 acme.sh(若未装)
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
  echo "    安装 acme.sh..."
  curl -fsSL https://get.acme.sh | sh -s email=admin@"$DOMAIN" >/dev/null 2>&1 || curl -fsSL https://get.acme.sh | sh
fi
ACME="$HOME/.acme.sh/acme.sh"
"$ACME" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

# 2. DuckDNS DNS-01 签证书(不需要 80 端口,避开备案拦截)
export DuckDNS_Token="$DUCKDNS_TOKEN"
echo "    申请证书(DNS-01)..."
# 不加 --force：证书已存在且有效时自动跳过，避免触发 Let's Encrypt 频率限制
"$ACME" --issue --dns dns_duckdns -d "$DOMAIN" || true

# 3. 安装证书到固定路径 + 续期后自动重启 TLS 服务
#    reloadcmd 容错：首次运行时服务尚未创建（下一步才建），失败不应中止脚本
mkdir -p /etc/levelit/tls
"$ACME" --install-cert -d "$DOMAIN" \
  --fullchain-file /etc/levelit/tls/fullchain.pem \
  --key-file       /etc/levelit/tls/privkey.pem \
  --reloadcmd      "systemctl restart levelit-tls 2>/dev/null || true"

# 4. systemd 服务
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

# 5. 放行系统防火墙(若启用)。注意:阿里云安全组需在控制台单独放行 8443!
command -v ufw >/dev/null 2>&1 && ufw allow 8443/tcp >/dev/null 2>&1 || true
command -v firewall-cmd >/dev/null 2>&1 && { firewall-cmd --add-port=8443/tcp --permanent >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1; } || true

if systemctl is-active --quiet levelit-tls; then
  echo "    ✓ levelit-tls 已启动"
else
  echo "    ✗ levelit-tls 启动失败:"; journalctl -u levelit-tls -n 20 --no-pager
  exit 1
fi
ENDSSH

echo ""
echo "==> 本机自测(从服务器内部,绕过安全组)..."
ssh "root@$SERVER" "curl -sk -o /dev/null -w 'HTTPS 本地 health: %{http_code}\n' https://localhost:8443/health"

echo ""
echo "==> 完成。接下来:"
echo "    1) 在【阿里云控制台 → 安全组】放行 8443/TCP 入站(脚本无法代劳)"
echo "    2) 放行后,本机验证: curl https://$DOMAIN:8443/health"
echo "    3) 我把 APIConfig 切到 https://$DOMAIN:8443 并去掉 ATS 例外"
