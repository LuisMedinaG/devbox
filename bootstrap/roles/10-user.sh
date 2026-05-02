#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# ADMIN_USERNAME: a separate account that holds unrestricted sudo.
# Defaults to the same as USERNAME so single-user setups still work,
# but production use should set them differently (e.g. ADMIN_USERNAME=admin).
: "${ADMIN_USERNAME:=$USERNAME}"
export ADMIN_USERNAME

# --- Interactive / agent user ($USERNAME) ---
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USERNAME"
fi

loginctl enable-linger "$USERNAME"

# Narrow sudo allowlist for $USERNAME: restart agent services only.
# No NOPASSWD:ALL — escalation requires the admin path.
mkdir -p /etc/sudoers.d
SUDOERS_TMP=$(mktemp)
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat >"$SUDOERS_TMP" <<EOF
# Narrow allowlist for $USERNAME — no blanket NOPASSWD:ALL
Defaults:$USERNAME requiretty, !visiblepw
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl restart agent-*, /bin/systemctl stop agent-*, /bin/systemctl start agent-*, /usr/bin/apt-get update
EOF
visudo -cf "$SUDOERS_TMP" >/dev/null
install -m 440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/90-"$USERNAME"

# --- Admin user ($ADMIN_USERNAME, may equal $USERNAME on dev boxes) ---
if [[ "$ADMIN_USERNAME" != "$USERNAME" ]]; then
  if ! id -u "$ADMIN_USERNAME" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$ADMIN_USERNAME"
  fi
  usermod -aG sudo "$ADMIN_USERNAME"

  ADMIN_SUDOERS_TMP=$(mktemp)
  trap 'rm -f "$ADMIN_SUDOERS_TMP"' EXIT
  printf 'Defaults:%s requiretty, !visiblepw, lecture=always\n%s ALL=(ALL) ALL\n' \
    "$ADMIN_USERNAME" "$ADMIN_USERNAME" >"$ADMIN_SUDOERS_TMP"
  visudo -cf "$ADMIN_SUDOERS_TMP" >/dev/null
  install -m 440 -o root -g root "$ADMIN_SUDOERS_TMP" /etc/sudoers.d/80-"$ADMIN_USERNAME"

  HOME_DIR_ADMIN="/home/$ADMIN_USERNAME"
  install -d -m 700 -o "$ADMIN_USERNAME" -g "$ADMIN_USERNAME" "$HOME_DIR_ADMIN/.ssh"
  ADMIN_KEYS_SRC="$SCRIPT_DIR/config/ssh-authorized-keys"
  [[ ! -f "$ADMIN_KEYS_SRC" ]] && [[ -f /root/.ssh/authorized_keys ]] && ADMIN_KEYS_SRC=/root/.ssh/authorized_keys
  if [[ -f "$ADMIN_KEYS_SRC" ]]; then
    install -m 600 -o "$ADMIN_USERNAME" -g "$ADMIN_USERNAME" \
      "$ADMIN_KEYS_SRC" "$HOME_DIR_ADMIN/.ssh/authorized_keys"
  fi
fi

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
