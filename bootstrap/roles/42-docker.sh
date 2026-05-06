#!/usr/bin/env bash
# Installs rootless Podman. The user is NOT added to any docker group.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# --- Rootless Podman ---
if ! command -v podman >/dev/null 2>&1; then
  apt_update_once
  apt_install podman slirp4netns fuse-overlayfs uidmap
fi

# Enable the per-user Podman socket so tooling can talk to it without root.
as_user 'systemctl --user enable --now podman.socket'

# VS Code Dev Containers looks for DOCKER_HOST or /var/run/docker.sock.
# Point it at the Podman socket so Dev Containers work without installing Docker.
PODMAN_SOCK_PATH="/run/user/$(id -u "$USERNAME")/podman/podman.sock"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
ensure_line "export DOCKER_HOST=unix://${PODMAN_SOCK_PATH}" "${USER_HOME}/.zshenv.local"

# Confirm rootless mode works for the user.
if ! as_user 'podman info --format "{{.Host.Security.Rootless}}"' 2>/dev/null | grep -q true; then
  warn "Podman rootless check did not return true — verify subuid/subgid entries for $USERNAME."
fi

# Ensure subuid/subgid ranges exist (adduser usually sets these; belt-and-suspenders).
if ! grep -q "^${USERNAME}:" /etc/subuid 2>/dev/null; then
  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USERNAME"
fi
