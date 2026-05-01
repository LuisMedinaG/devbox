#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

as_user '
  export PATH="$HOME/.fnm:$PATH"
  eval "$($HOME/.fnm/fnm env)"
  if ! command -v claude >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code
  else
    npm update -g @anthropic-ai/claude-code || true
  fi
'

log "Run 'claude' as $USERNAME to complete device-flow auth."
