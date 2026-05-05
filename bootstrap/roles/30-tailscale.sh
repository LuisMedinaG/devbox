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
    tailscale up --ssh --authkey "$TS_AUTHKEY" \
      --hostname devbox \
      --advertise-tags=tag:devbox
  else
    warn "Run: sudo tailscale up --ssh --hostname devbox --advertise-tags=tag:devbox"
  fi
fi

# Restrict SSH to Tailscale CGNAT range only — public port 22 is closed.
# Tailscale SSH (--ssh above) remains the sole access path; traditional SSH
# keys are kept as a fallback reachable only through the Tailscale overlay.
if [[ "${SKIP_FIREWALL:-0}" == "0" ]] && ufw status 2>/dev/null | grep -q '^Status: active'; then
  if tailscale status >/dev/null 2>&1; then
    ufw delete allow OpenSSH >/dev/null 2>&1 || true
    ufw allow from 100.64.0.0/10 to any port 22 comment "SSH via Tailscale only" >/dev/null
  else
    warn "Tailscale not connected — port 22 remains open; re-run role 30 after 'tailscale up'"
  fi
fi
