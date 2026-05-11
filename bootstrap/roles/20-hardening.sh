#!/usr/bin/env bash
# Role 20: SSH hardening and fail2ban only.
# UFW firewall rules live in role 31-firewall, which runs after Tailscale (role 30)
# so that port 22 is never closed before the Tailscale overlay is available.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install fail2ban

# Harden SSH via a drop-in. Ubuntu 24.04's stock sshd_config Includes
# /etc/ssh/sshd_config.d/*.conf, so we don't have to mutate the upstream file.
# bootstrap.HARDENING.1 bootstrap.HARDENING.2 bootstrap.HARDENING.3
# bootstrap.HARDENING.7 — SKIP_SSH_HARDENING escape hatch for dev iteration
if [[ "${SKIP_SSH_HARDENING:-0}" = "1" ]]; then
  warn "SKIP_SSH_HARDENING=1 — leaving sshd_config.d/10-hardening.conf unwritten."
  warn "  Public root SSH stays open. DO NOT use this in production."
  # Remove any previous hardening drop-in so re-running with the flag actually
  # relaxes the config instead of silently keeping the prior state.
  rm -f /etc/ssh/sshd_config.d/10-hardening.conf
else
  install -d -m 755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
EOF
  chmod 644 /etc/ssh/sshd_config.d/10-hardening.conf
fi

# Privilege-separation dir is normally created by systemd-tmpfiles, but on
# some images it goes missing, which makes `sshd -t` abort before it can
# even validate the config. Create it ourselves to keep re-runs idempotent.
install -d -m 755 /run/sshd

sshd -t
reload_sshd

# Explicitly enable ssh so it starts on boot — some images have it disabled.
# Ubuntu 24.04 uses socket-based activation by default (ssh.socket), but
# ensuring ssh.service is enabled provides defense-in-depth.
enable_service ssh

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
