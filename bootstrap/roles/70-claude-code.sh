#!/usr/bin/env bash
# Role 70: Install Claude Code and claude-mem MCP server (Node managed by mise via role 60).
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! as_user 'command -v claude >/dev/null 2>&1'; then
  log "Installing Claude Code ..."
  as_user 'mise exec node -- npm install -g @anthropic-ai/claude-code'
  log "Claude Code installed."
else
  log "Claude Code already installed — skipping."
fi

PLUGIN_CACHE_DIR="$USER_HOME/.claude/plugins/cache/thedotmack/claude-mem"
if [ ! -d "$PLUGIN_CACHE_DIR" ]; then
  log "Installing claude-mem MCP server ..."
  as_user 'mise exec node -- npx --yes claude-mem install'
  log "claude-mem installed."
else
  log "claude-mem already installed — skipping."
fi
