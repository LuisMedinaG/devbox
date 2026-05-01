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

# Skip ufw/fail2ban when SKIP_UFW=1 (e.g. Fly.io — no public ports, handled at Fly layer).
if [[ -z "${SKIP_UFW:-}" ]]; then
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw --force enable
  enable_service fail2ban /usr/sbin/fail2ban-server
fi
