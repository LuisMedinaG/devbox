#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install ufw fail2ban

# Harden SSH.
SSHD=/etc/ssh/sshd_config
ensure_kv "PermitRootLogin"        "no"  "$SSHD"
ensure_kv "PasswordAuthentication" "no"  "$SSHD"
ensure_kv "PubkeyAuthentication"   "yes" "$SSHD"
ensure_kv "KbdInteractiveAuthentication" "no" "$SSHD"
ensure_kv "ChallengeResponseAuthentication" "no" "$SSHD"
ensure_kv "X11Forwarding"          "no"  "$SSHD"

sshd -t
reload_sshd

if [[ "${SKIP_UFW:-0}" == "0" ]]; then
  # Only initialize ufw if it isn't already active. Re-running this role must
  # not wipe rules added by later roles (e.g. docker stacks opening ports).
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow OpenSSH
    ufw allow 60000:61000/udp    # mosh
    ufw --force enable
  else
    # Ensure the baseline rules exist even on re-run; ufw dedupes.
    ufw allow OpenSSH >/dev/null
    ufw allow 60000:61000/udp >/dev/null
  fi
  enable_service fail2ban
fi
