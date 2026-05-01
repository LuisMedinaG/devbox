#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

enable_service tailscaled /usr/sbin/tailscaled

if ! tailscale status >/dev/null 2>&1; then
  if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale up --ssh --authkey "$TS_AUTHKEY" --accept-routes
  else
    warn "Run: sudo tailscale up --ssh   (no TS_AUTHKEY provided)"
  fi
fi
