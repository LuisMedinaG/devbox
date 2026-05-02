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

# Go. Arch-aware + sha256-verified against go.dev/dl metadata so a CDN
# compromise can't silently feed root a different tarball.
GO_VERSION="1.23.4"
case "$(dpkg --print-architecture)" in
  amd64) GO_ARCH=amd64 ;;
  arm64) GO_ARCH=arm64 ;;
  *) die "Unsupported architecture for Go: $(dpkg --print-architecture)" ;;
esac
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q "go${GO_VERSION} "; then
  GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
  GO_SHA256=$(curl -fsSL "https://go.dev/dl/?mode=json&include=all" \
    | jq -r --arg v "go${GO_VERSION}" --arg f "$GO_TARBALL" \
        '.[] | select(.version==$v) | .files[] | select(.filename==$f) | .sha256')
  [[ -n "$GO_SHA256" ]] || die "Could not look up sha256 for $GO_TARBALL"
  curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o /tmp/go.tgz
  echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c -
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  rm /tmp/go.tgz
fi
