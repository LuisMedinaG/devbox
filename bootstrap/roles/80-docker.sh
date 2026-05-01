#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

usermod -aG docker "$USERNAME"
enable_service docker /usr/bin/dockerd

install -d -o "$USERNAME" -g "$USERNAME" /srv/stacks
