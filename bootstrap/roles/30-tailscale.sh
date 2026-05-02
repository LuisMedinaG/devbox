#!/usr/bin/env bash
# Installs Tailscale from the official signed apt repo — no curl|sh.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! command -v tailscale >/dev/null 2>&1; then
  apt_update_once
  apt_install curl gpg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/tailscale.gpg
  chmod a+r /etc/apt/keyrings/tailscale.gpg

  echo "deb [signed-by=/etc/apt/keyrings/tailscale.gpg] \
https://pkgs.tailscale.com/stable/ubuntu noble main" \
    >/etc/apt/sources.list.d/tailscale.list

  apt-get update -y
  mkdir -p /var/lib/bootstrap && touch /var/lib/bootstrap/apt-updated
  apt_install tailscale
fi

enable_service tailscaled

if ! tailscale status >/dev/null 2>&1; then
  if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale up --ssh --authkey "$TS_AUTHKEY" --accept-routes
  else
    warn "Run: sudo tailscale up --ssh   (no TS_AUTHKEY provided)"
  fi
fi
