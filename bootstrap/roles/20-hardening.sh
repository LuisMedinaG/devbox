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
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 60000:61000/udp    # mosh
  ufw --force enable
  enable_service fail2ban
fi
