#!/usr/bin/env bash
# Role 31: UFW firewall — runs after Tailscale (role 30) so port 22 is never
# closed before the Tailscale overlay is available. If this role fails or is
# skipped, public SSH remains open, which is safe for recovery.
# bootstrap.HARDENING.4 bootstrap.HARDENING.5 bootstrap.TAILSCALE.5
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install ufw

if [[ "${SKIP_FIREWALL:-0}" != "0" ]]; then
  log "SKIP_FIREWALL set — skipping UFW setup."
  exit 0
fi

# Only initialize ufw if it isn't already active. Re-running this role must
# not wipe rules added by other roles (e.g. services opening extra ports).
if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 60000:61000/udp    # mosh
  ufw --force enable
else
  # Ensure baseline rules exist on re-run; ufw dedupes.
  ufw allow OpenSSH >/dev/null
  ufw allow 60000:61000/udp >/dev/null
fi

# Restrict SSH to Tailscale CGNAT range only — public port 22 is closed.
# Only do this if Tailscale is connected; otherwise leave OpenSSH open so the
# operator can still recover via public SSH.
if tailscale status >/dev/null 2>&1; then
  ufw delete allow OpenSSH >/dev/null 2>&1 || true
  ufw allow from 100.64.0.0/10 to any port 22 comment "SSH via Tailscale only" >/dev/null
  log "Port 22 restricted to Tailscale CGNAT range."
else
  warn "Tailscale not connected — port 22 remains open on public IP."
  warn "Re-run role 31-firewall after 'tailscale up' to restrict it."
fi
