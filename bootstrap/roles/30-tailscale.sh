#!/usr/bin/env bash
# Installs Tailscale from the official signed apt repo — no curl|sh.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# bootstrap.TAILSCALE.1
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

# bootstrap.TAILSCALE.2 bootstrap.TAILSCALE.3
: "${MACHINE_NAME:=devbox}"
: "${TS_TAG:=tag:${MACHINE_NAME}}"

if ! tailscale status >/dev/null 2>&1; then
  if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale up --ssh --authkey "$TS_AUTHKEY" \
      --hostname "$MACHINE_NAME" \
      --advertise-tags="$TS_TAG"
      # Note: this role runs in a child bash process; clearing TS_AUTHKEY here
      # does not affect the parent. The parent bootstrap.sh unsets it after
      # this role completes (search "unset TS_AUTHKEY" in bootstrap.sh).
      # bootstrap.TAILSCALE.3-1
  else
    warn "Run: sudo tailscale up --ssh --hostname $MACHINE_NAME --advertise-tags=$TS_TAG"
  fi
fi

# Port 22 restriction (CGNAT-only) is handled by role 31-firewall, which runs
# after this role. bootstrap.TAILSCALE.5
