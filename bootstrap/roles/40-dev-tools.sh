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
  age \
  neovim \
  zoxide \
  yadm \
  mosh   # the metapackage; pulls mosh-server which UFW exposes on 60000-61000/udp

[[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind /usr/local/bin/fd
[[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat /usr/local/bin/bat

# eza — not in Ubuntu main repos; official signed deb repo
if ! command -v eza >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/gierens.gpg] \
http://deb.gierens.de stable main" \
    > /etc/apt/sources.list.d/gierens.list
  chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  apt-get update -qq
  apt_install eza
fi
