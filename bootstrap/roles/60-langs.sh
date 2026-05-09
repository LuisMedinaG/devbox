#!/usr/bin/env bash
# Installs mise and a global tool config; mise installs runtimes on first use.
# bootstrap.LANGS.1 bootstrap.LANGS.2 bootstrap.LANGS.3 bootstrap.LANGS.4 bootstrap.LANGS.5
# bootstrap.LANGS.6 bootstrap.LANGS.7 bootstrap.LANGS.8
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

VERSIONS_CONF="$SCRIPT_DIR/config/versions.conf"
[[ -f "$VERSIONS_CONF" ]] || die "config/versions.conf not found."
# shellcheck source=/dev/null
source "$VERSIONS_CONF"

# bootstrap.LANGS.6
: "${MISE_VERSION:?Set MISE_VERSION in config/versions.conf}"
: "${MISE_SHA256_AMD64:?Set MISE_SHA256_AMD64 in config/versions.conf}"
: "${MISE_SHA256_ARM64:?Set MISE_SHA256_ARM64 in config/versions.conf}"

# bootstrap.LANGS.8
case "$(dpkg --print-architecture)" in
  amd64) ARCH=x64;   MISE_SHA256="$MISE_SHA256_AMD64" ;;
  arm64) ARCH=arm64; MISE_SHA256="$MISE_SHA256_ARM64" ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

# bootstrap.LANGS.7
if ! command -v mise >/dev/null 2>&1; then
  log "Installing mise ${MISE_VERSION} ..."
  MISE_URL="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${ARCH}"
  download_verify "$MISE_URL" /tmp/mise "$MISE_SHA256"
  install -m 755 /tmp/mise /usr/local/bin/mise
  rm -f /tmp/mise
fi

MISE_CONFIG="$USER_HOME/.config/mise/config.toml"
if [[ ! -f "$MISE_CONFIG" ]]; then
  make_user_dir "$USER_HOME/.config/mise"
  cat > "$MISE_CONFIG" <<'EOF'
[tools]
node   = "lts"
python = "latest"
go     = "latest"
rust   = "stable"
bun    = "latest"
EOF
  chown "$USERNAME:$USERNAME" "$MISE_CONFIG"
fi

# bootstrap.LANGS.1 bootstrap.LANGS.2 bootstrap.LANGS.3 bootstrap.LANGS.4 bootstrap.LANGS.5
log "Installing mise-managed runtimes ..."
as_user 'mise install'
