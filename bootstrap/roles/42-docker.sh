#!/usr/bin/env bash
# Installs rootless Podman (primary runtime for agents) and, optionally,
# rootful Docker with userns-remap so UID 0 inside containers != host root.
# The interactive/agent user is NOT added to the docker group.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# --- Rootless Podman ---
if ! command -v podman >/dev/null 2>&1; then
  apt_update_once
  apt_install podman slirp4netns fuse-overlayfs uidmap
fi

# Enable the per-user Podman socket so tooling can talk to it without root.
as_user 'systemctl --user enable --now podman.socket'

# Confirm rootless mode works for the user.
if ! as_user 'podman info --format "{{.Host.Security.Rootless}}"' 2>/dev/null | grep -q true; then
  warn "Podman rootless check did not return true — verify subuid/subgid entries for $USERNAME."
fi

# Ensure subuid/subgid ranges exist (adduser usually sets these; belt-and-suspenders).
if ! grep -q "^${USERNAME}:" /etc/subuid 2>/dev/null; then
  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USERNAME"
fi

# --- Docker (optional, hardened) ---
# Set INSTALL_DOCKER=1 to include rootful Docker with userns-remap.
# Agents must not be given docker group membership; Docker is for host-level stacks only.
if [[ "${INSTALL_DOCKER:-0}" == "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
      >/etc/apt/sources.list.d/docker.list

    apt-get update -y
    mkdir -p /var/lib/bootstrap && touch /var/lib/bootstrap/apt-updated
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  # Harden the daemon: userns-remap so container UID 0 != host UID 0,
  # journald logging, no inter-container comms by default, no new privileges.
  install -d /etc/docker
  cat >/etc/docker/daemon.json <<'EOF'
{
  "userns-remap": "default",
  "log-driver": "journald",
  "no-new-privileges": true,
  "icc": false,
  "live-restore": true
}
EOF

  enable_service docker

  # Explicitly do NOT add $USERNAME to the docker group.
  # Per-service stacks live under /srv/stacks owned by per-service system users.
  install -d -o root -g root /srv/stacks
  log "Docker installed with userns-remap. '$USERNAME' is NOT in the docker group."
fi
