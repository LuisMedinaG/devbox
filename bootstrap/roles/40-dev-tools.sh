#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_update_once
apt_install \
  build-essential pkg-config \
  git git-lfs curl wget jq \
  tmux zsh \
  ripgrep fd-find bat fzf \
  htop btop ncdu tree \
  unzip zip xz-utils \
  ca-certificates gnupg \
  python3 python3-venv python3-pip \
  age

[[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind /usr/local/bin/fd
[[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat /usr/local/bin/bat
