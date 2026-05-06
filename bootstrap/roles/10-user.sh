#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# --- User ($USERNAME) ---
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USERNAME"
fi

loginctl enable-linger "$USERNAME"

# Narrow sudo allowlist — no NOPASSWD:ALL.
# /usr/bin/apt-get update: limited package list refresh only.
mkdir -p /etc/sudoers.d
SUDOERS_TMP=$(mktemp)
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat >"$SUDOERS_TMP" <<EOF
# Narrow allowlist for $USERNAME — no blanket NOPASSWD:ALL
Defaults:$USERNAME requiretty, !visiblepw
$USERNAME ALL=(root) NOPASSWD: /usr/bin/apt-get update
EOF
visudo -cf "$SUDOERS_TMP" >/dev/null
install -m 440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/90-"$USERNAME"

# --- SSH keys for $USERNAME ---
HOME_DIR="/home/$USERNAME"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/.ssh"

# Prefer an explicit key file; fall back to the key Hetzner injected for root.
# Role 20 disables PasswordAuthentication, so no keys = locked out.
KEYS_SRC="$SCRIPT_DIR/config/ssh-authorized-keys"
if [[ ! -f "$KEYS_SRC" ]]; then
  if [[ -f /root/.ssh/authorized_keys ]]; then
    KEYS_SRC=/root/.ssh/authorized_keys
    warn "config/ssh-authorized-keys not found — using /root/.ssh/authorized_keys (injected by Hetzner)"
  else
    die "No SSH keys found. Provide config/ssh-authorized-keys or create the server with --ssh-key."
  fi
fi
install -m 600 -o "$USERNAME" -g "$USERNAME" "$KEYS_SRC" "$HOME_DIR/.ssh/authorized_keys"
