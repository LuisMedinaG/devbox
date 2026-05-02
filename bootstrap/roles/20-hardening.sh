#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install ufw fail2ban

# Harden SSH via a drop-in. Ubuntu 24.04's stock sshd_config Includes
# /etc/ssh/sshd_config.d/*.conf, so we don't have to mutate the upstream file.
install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
EOF
chmod 644 /etc/ssh/sshd_config.d/10-hardening.conf

sshd -t
reload_sshd

if [[ "${SKIP_FIREWALL:-0}" == "0" ]]; then
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
