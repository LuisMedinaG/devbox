#!/usr/bin/env bash
# Installs mise and a global tool config; mise installs runtimes on first use.
# bootstrap.LANGS.1 bootstrap.LANGS.2 bootstrap.LANGS.3 bootstrap.LANGS.4 bootstrap.LANGS.5
# bootstrap.LANGS.6 bootstrap.LANGS.7 bootstrap.LANGS.8
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

# bootstrap.LANGS.6 bootstrap.LANGS.8
source_versions
detect_arch MISE

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
