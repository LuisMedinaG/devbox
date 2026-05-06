#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install ufw fail2ban

# Harden SSH via a drop-in. Ubuntu 24.04's stock sshd_config Includes
# /etc/ssh/sshd_config.d/*.conf, so we don't have to mutate the upstream file.
# bootstrap.HARDENING.1 bootstrap.HARDENING.2 bootstrap.HARDENING.3
install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
EOF
chmod 644 /etc/ssh/sshd_config.d/10-hardening.conf

# Privilege-separation dir is normally created by systemd-tmpfiles, but on
# some images it goes missing, which makes `sshd -t` abort before it can
# even validate the config. Create it ourselves to keep re-runs idempotent.
install -d -m 755 /run/sshd

sshd -t
reload_sshd

# bootstrap.HARDENING.4 bootstrap.HARDENING.5
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
fi

# fail2ban is independent of UFW — SSH brute-force protection should run even
# when SKIP_FIREWALL=1 (which is meant to skip ufw, not all defenses).
# Ubuntu 24.04's fail2ban ships without any jails active by default, so
# installing it without jail.local leaves the service running but doing nothing.
# bootstrap.HARDENING.6
cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
EOF
enable_service fail2ban
