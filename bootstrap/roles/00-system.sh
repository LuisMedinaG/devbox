#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_update_once
apt_install ca-certificates curl gnupg lsb-release tzdata sudo

# bootstrap.SYSTEM.1
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Suppress MOTD noise: ESM ads and pending-update counts that alarm on every login.
# Unattended-upgrades handles patching automatically + reboots nightly if needed.
for motd in /etc/update-motd.d/90-updates-available /etc/update-motd.d/95-hwe-eol /etc/update-motd.d/91-release-upgrade; do
  [[ -x "$motd" ]] && chmod -x "$motd" || true
done
if [[ -x /usr/lib/update-notifier/apt_check.py ]]; then
  mv /usr/lib/update-notifier/apt_check.py /usr/lib/update-notifier/apt_check.py.disabled
fi

# Apply security patches automatically and reboot at 02:00 if required.
# Without Automatic-Reboot, kernel CVE patches install but never activate.
# bootstrap.SYSTEM.2
cat >/etc/apt/apt.conf.d/51unattended-upgrades-reboot <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOF

# Rotate bootstrap logs weekly; keep 8 weeks. Without this, long-lived
# hosts accumulate unbounded logs under /var/log/bootstrap/.
# bootstrap.SYSTEM.5
cat >/etc/logrotate.d/bootstrap <<'EOF'
/var/log/bootstrap/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF

# bootstrap.SYSTEM.3
SWAPFILE="${SWAPFILE:-/swapfile}"
if ! swapon --show | grep -q .; then
  fallocate -l 2G "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"
  ensure_line "$SWAPFILE none swap sw 0 0" /etc/fstab
fi

# bootstrap.SYSTEM.4
cat >/etc/sysctl.d/99-bootstrap.conf <<'EOF'
vm.swappiness=10
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null

# Apply all pending upgrades now (fresh image has ~100+ backlog).
# After this, unattended-upgrades handles ongoing security patches.
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
