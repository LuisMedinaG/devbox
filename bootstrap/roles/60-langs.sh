#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# Node via fnm.
as_user '
  if [[ ! -d "$HOME/.fnm" ]]; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "$HOME/.fnm"
  fi
  export PATH="$HOME/.fnm:$PATH"
  eval "$($HOME/.fnm/fnm env)"
  fnm install --lts
  fnm default lts-latest
'

# Python: uv.
as_user '
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
'

# Rust.
as_user '
  if [[ ! -d "$HOME/.cargo" ]]; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
  fi
'

# Go.
GO_VERSION="1.23.4"
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q "$GO_VERSION"; then
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  rm /tmp/go.tgz
fi
