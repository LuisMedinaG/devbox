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

# agent-service-ctl: validated wrapper around systemctl for agent-*.service units.
# sudo's command glob matching does not expand shell globs in argument position,
# so `systemctl restart agent-*` in sudoers would not match actual unit names.
# This wrapper validates the action and unit name itself, then calls systemctl.
AGENT_SVC_CTL="/usr/local/sbin/agent-service-ctl"
cat >"$AGENT_SVC_CTL" <<'SVCCTL'
#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
UNIT="${2:-}"
case "$ACTION" in
  start|stop|restart|status) ;;
  *) echo "Usage: agent-service-ctl <start|stop|restart|status> <agent-*.service>" >&2; exit 1;;
esac
[[ "$UNIT" =~ ^agent-[a-z][a-z0-9_-]*\.service$ ]] || {
  echo "Error: unit must match agent-<name>.service" >&2; exit 1
}
exec /bin/systemctl "$ACTION" "$UNIT"
SVCCTL
chmod 755 "$AGENT_SVC_CTL"

# Narrow sudo allowlist for $USERNAME — no NOPASSWD:ALL.
# /usr/local/bin/agent-run: runs the agent sandbox (drops to agent user via
#   runuser inside the wrapper; caller supplies only workspace name + -e flags).
# /usr/local/sbin/agent-service-ctl: validated systemctl for agent-*.service.
# /usr/bin/apt-get update: limited package list refresh only.
mkdir -p /etc/sudoers.d
SUDOERS_TMP=$(mktemp)
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat >"$SUDOERS_TMP" <<EOF
# Narrow allowlist for $USERNAME — no blanket NOPASSWD:ALL
Defaults:$USERNAME requiretty, !visiblepw
$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/agent-run, /usr/local/sbin/agent-service-ctl, /usr/bin/apt-get update
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
