#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USERNAME"
fi

usermod -aG sudo "$USERNAME"
loginctl enable-linger "$USERNAME"

mkdir -p /etc/sudoers.d
SUDOERS_TMP=$(mktemp)
trap 'rm -f "$SUDOERS_TMP"' EXIT
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" >"$SUDOERS_TMP"
visudo -cf "$SUDOERS_TMP" >/dev/null
install -m 440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/90-"$USERNAME"

HOME_DIR="/home/$USERNAME"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/.ssh"

if [[ -f "$SCRIPT_DIR/config/ssh-authorized-keys" ]]; then
  install -m 600 -o "$USERNAME" -g "$USERNAME" \
    "$SCRIPT_DIR/config/ssh-authorized-keys" \
    "$HOME_DIR/.ssh/authorized_keys"
else
  warn "config/ssh-authorized-keys missing — add your pubkeys before disabling root!"
fi
