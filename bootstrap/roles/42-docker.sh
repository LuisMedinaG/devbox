#!/usr/bin/env bash
# Installs rootless Podman. The user is NOT added to any docker group.
# bootstrap.DOCKER.1 bootstrap.DOCKER.2
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# --- Rootless Podman ---
if ! command -v podman >/dev/null 2>&1; then
  apt_update_once
  apt_install podman slirp4netns fuse-overlayfs uidmap
fi

# Enable the per-user Podman socket so tooling can talk to it without root.
# bootstrap.DOCKER.4
# systemctl --user requires a D-Bus session which doesn't exist during bootstrap.
# Directly create the systemd wants symlink instead — equivalent to `systemctl --user enable`.
# Linger (set in role 10) ensures the socket auto-starts on boot without a login.
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
WANTS_DIR="${USER_HOME}/.config/systemd/user/default.target.wants"
SOCKET_UNIT="/usr/lib/systemd/user/podman.socket"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" \
  "${USER_HOME}/.config" \
  "${USER_HOME}/.config/systemd" \
  "${USER_HOME}/.config/systemd/user" \
  "${WANTS_DIR}"
if [[ -f "$SOCKET_UNIT" ]] && [[ ! -L "${WANTS_DIR}/podman.socket" ]]; then
  ln -s "$SOCKET_UNIT" "${WANTS_DIR}/podman.socket"
  chown -h "$USERNAME":"$USERNAME" "${WANTS_DIR}/podman.socket"
fi

# VS Code Dev Containers looks for DOCKER_HOST or /var/run/docker.sock.
# Point it at the Podman socket so Dev Containers work without installing Docker.
# bootstrap.DOCKER.5
PODMAN_SOCK_PATH="/run/user/$(id -u "$USERNAME")/podman/podman.sock"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
ensure_line "export DOCKER_HOST=unix://${PODMAN_SOCK_PATH}" "${USER_HOME}/.zshenv.local"

# bootstrap.DOCKER.3
# Rootless check requires a running user session — skip during bootstrap, assert in e2e.bats.
warn "Podman rootless check skipped during bootstrap (no user session). Verified by e2e.bats after login."

# Ensure subuid/subgid ranges exist (adduser usually sets these; belt-and-suspenders).
# bootstrap.DOCKER.6
if ! grep -q "^${USERNAME}:" /etc/subuid 2>/dev/null; then
  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USERNAME"
fi
