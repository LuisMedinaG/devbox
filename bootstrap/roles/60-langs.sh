#!/usr/bin/env bash
# Installs language runtimes. Every third-party binary is downloaded at a
# pinned version and verified against a sha256 from config/versions.conf
# before execution. No curl|sh.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

VERSIONS_CONF="$SCRIPT_DIR/config/versions.conf"
[[ -f "$VERSIONS_CONF" ]] || die "config/versions.conf not found."
# shellcheck source=/dev/null
source "$VERSIONS_CONF"

# Require explicit sha256 for every tool; die early with a clear message.
: "${FNM_VERSION:?Set FNM_VERSION in config/versions.conf}"
: "${FNM_SHA256:?Set FNM_SHA256 in config/versions.conf}"

: "${UV_VERSION:?Set UV_VERSION in config/versions.conf}"
: "${UV_SHA256_AMD64:?Set UV_SHA256_AMD64 in config/versions.conf}"
: "${UV_SHA256_ARM64:?Set UV_SHA256_ARM64 in config/versions.conf}"

: "${BUN_VERSION:?Set BUN_VERSION in config/versions.conf}"
: "${BUN_SHA256_AMD64:?Set BUN_SHA256_AMD64 in config/versions.conf}"
: "${BUN_SHA256_ARM64:?Set BUN_SHA256_ARM64 in config/versions.conf}"

: "${RUSTUP_VERSION:?Set RUSTUP_VERSION in config/versions.conf}"
: "${RUSTUP_SHA256_AMD64:?Set RUSTUP_SHA256_AMD64 in config/versions.conf}"
: "${RUSTUP_SHA256_ARM64:?Set RUSTUP_SHA256_ARM64 in config/versions.conf}"

: "${GO_VERSION:?Set GO_VERSION in config/versions.conf}"
: "${GO_SHA256_AMD64:?Set GO_SHA256_AMD64 in config/versions.conf}"
: "${GO_SHA256_ARM64:?Set GO_SHA256_ARM64 in config/versions.conf}"

apt_update_once
apt_install curl unzip

case "$(dpkg --print-architecture)" in
  amd64) ARCH=amd64 ;;
  arm64) ARCH=arm64 ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

# --- Node via fnm ---
# fnm-linux.zip is a single binary for all arches; one sha256 covers both.
if ! as_user '[[ -x "$HOME/.fnm/fnm" ]]'; then
  log "Installing fnm ${FNM_VERSION} ..."
  FNM_URL="https://github.com/Schniz/fnm/releases/download/v${FNM_VERSION}/fnm-linux.zip"
  TMP_ZIP=$(mktemp --suffix=.zip)
  download_verify "$FNM_URL" "$TMP_ZIP" "$FNM_SHA256"
  TMP_DIR=$(mktemp -d)
  unzip -q "$TMP_ZIP" -d "$TMP_DIR"
  install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.fnm"
  install -m 755 -o "$USERNAME" -g "$USERNAME" "$TMP_DIR/fnm" "/home/$USERNAME/.fnm/fnm"
  rm -rf "$TMP_ZIP" "$TMP_DIR"
fi
as_user '
  export PATH="$HOME/.fnm:$PATH"
  eval "$(fnm env)"
  fnm install --lts
  fnm default lts-latest
'

# --- Python: uv ---
if ! as_user 'command -v uv >/dev/null 2>&1'; then
  log "Installing uv ${UV_VERSION} ..."
  UV_SHA256_VAR="UV_SHA256_${ARCH^^}"
  case "$ARCH" in
    amd64) UV_TRIPLE="x86_64-unknown-linux-musl" ;;
    arm64) UV_TRIPLE="aarch64-unknown-linux-musl" ;;
  esac
  UV_TARBALL="uv-${UV_TRIPLE}.tar.gz"
  UV_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_TARBALL}"
  TMP_TGZ=$(mktemp --suffix=.tar.gz)
  download_verify "$UV_URL" "$TMP_TGZ" "${!UV_SHA256_VAR}"
  TMP_DIR=$(mktemp -d)
  tar -xzf "$TMP_TGZ" -C "$TMP_DIR" --strip-components=1
  install -m 755 -o "$USERNAME" -g "$USERNAME" "$TMP_DIR/uv" "/home/$USERNAME/.local/bin/uv"
  install -m 755 -o "$USERNAME" -g "$USERNAME" "$TMP_DIR/uvx" "/home/$USERNAME/.local/bin/uvx"
  rm -rf "$TMP_TGZ" "$TMP_DIR"
fi

# --- Bun ---
if ! as_user 'command -v bun >/dev/null 2>&1'; then
  log "Installing bun ${BUN_VERSION} ..."
  BUN_SHA256_VAR="BUN_SHA256_${ARCH^^}"
  case "$ARCH" in
    amd64) BUN_TAG="bun-linux-x64-baseline" ;;
    arm64) BUN_TAG="bun-linux-aarch64" ;;
  esac
  BUN_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_TAG}.zip"
  TMP_ZIP=$(mktemp --suffix=.zip)
  download_verify "$BUN_URL" "$TMP_ZIP" "${!BUN_SHA256_VAR}"
  TMP_DIR=$(mktemp -d)
  unzip -q "$TMP_ZIP" -d "$TMP_DIR"
  install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.bun/bin"
  install -m 755 -o "$USERNAME" -g "$USERNAME" "$TMP_DIR/${BUN_TAG}/bun" "/home/$USERNAME/.bun/bin/bun"
  rm -rf "$TMP_ZIP" "$TMP_DIR"
fi

# --- Rust via rustup-init ---
if ! as_user '[[ -d "$HOME/.cargo" ]]'; then
  log "Installing rustup ${RUSTUP_VERSION} ..."
  RUSTUP_SHA256_VAR="RUSTUP_SHA256_${ARCH^^}"
  case "$ARCH" in
    amd64) RUSTUP_TRIPLE="x86_64-unknown-linux-gnu" ;;
    arm64) RUSTUP_TRIPLE="aarch64-unknown-linux-gnu" ;;
  esac
  RUSTUP_URL="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${RUSTUP_TRIPLE}/rustup-init"
  TMP_INIT=$(mktemp)
  download_verify "$RUSTUP_URL" "$TMP_INIT" "${!RUSTUP_SHA256_VAR}"
  chmod +x "$TMP_INIT"
  sudo -u "$USERNAME" -H "$TMP_INIT" -y --no-modify-path
  rm -f "$TMP_INIT"
fi

# --- Go ---
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q "go${GO_VERSION} "; then
  log "Installing Go ${GO_VERSION} ..."
  GO_SHA256_VAR="GO_SHA256_${ARCH^^}"
  GO_TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"
  download_verify "https://go.dev/dl/${GO_TARBALL}" /tmp/go.tgz "${!GO_SHA256_VAR}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  rm /tmp/go.tgz
fi
