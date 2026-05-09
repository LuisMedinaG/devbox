#!/usr/bin/env bash
# Installs Caddy from the official signed apt repo; writes a base Caddyfile with
# a health endpoint and conf.d include pattern for future service snippets.
# bootstrap.CADDY.1 bootstrap.CADDY.2 bootstrap.CADDY.3 bootstrap.CADDY.4 bootstrap.CADDY.5
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

CADDY_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
CADDY_SOURCES="/etc/apt/sources.list.d/caddy-stable.list"

# bootstrap.CADDY.1
if ! command -v caddy >/dev/null 2>&1; then
  apt_install gpg
  if [[ ! -f "$CADDY_KEYRING" ]]; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o "$CADDY_KEYRING"
  fi
  if [[ ! -f "$CADDY_SOURCES" ]]; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee "$CADDY_SOURCES" >/dev/null
    apt-get update -y
  fi
  apt_install caddy
fi

# bootstrap.CADDY.2 bootstrap.CADDY.3
mkdir -p /etc/caddy/conf.d
if ! grep -q "bootstrap.CADDY" /etc/caddy/Caddyfile 2>/dev/null; then
  cat > /etc/caddy/Caddyfile <<'EOF'
# bootstrap.CADDY
{
    email betousky01@gmail.com
}

:80 {
    handle /health {
        respond "OK" 200
    }
}

import /etc/caddy/conf.d/*.conf
EOF
  systemctl is-active --quiet caddy 2>/dev/null && systemctl reload caddy || true
fi

# bootstrap.CADDY.4
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp  >/dev/null
  ufw allow 443/tcp >/dev/null
fi

# bootstrap.CADDY.5
enable_service caddy
