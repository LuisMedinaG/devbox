#!/usr/bin/env bash
# Role 80: Install Claude Code globally via npm (Node installed by role 60).
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if as_user 'command -v claude >/dev/null 2>&1'; then
  log "Claude Code already installed — skipping."
  exit 0
fi

log "Installing Claude Code ..."
as_user '
  export PATH="$HOME/.fnm:$PATH"
  eval "$(fnm env)"
  npm install -g @anthropic-ai/claude-code
'
log "Claude Code installed."
