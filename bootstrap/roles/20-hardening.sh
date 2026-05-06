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
