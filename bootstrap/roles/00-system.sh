#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_update_once
apt_install ca-certificates curl gnupg lsb-release tzdata

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# 2 GB swap if none exists.
# Use /home/swapfile so it lives on the persistent volume (root may be overlayfs).
SWAPFILE="${SWAPFILE:-/home/swapfile}"
if ! swapon --show | grep -q .; then
  fallocate -l 2G "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"
  ensure_line "$SWAPFILE none swap sw 0 0" /etc/fstab
fi

cat >/etc/sysctl.d/99-bootstrap.conf <<'EOF'
vm.swappiness=10
net.ipv4.tcp_bbr=1
net.core.default_qdisc=fq
EOF
sysctl --system >/dev/null
