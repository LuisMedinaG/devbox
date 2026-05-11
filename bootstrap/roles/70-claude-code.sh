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
  # claude-mem detects interactivity via process.stdin.isTTY. When non-TTY it
  # silently picks recommended defaults: ide=claude-code, runtime=worker,
  # provider=claude, auth=subscription, model=claude-haiku-4-5-20251001.
  # We force </dev/null so the install stays non-interactive even when a
  # human is running bootstrap manually over an SSH TTY.
  # --no-auto-start: defensive — non-TTY already skips worker spawn; we start
  # it explicitly below so the worker is up after bootstrap finishes.
  as_user 'mise exec node -- npx --yes claude-mem install --no-auto-start </dev/null'
  log "claude-mem installed."
else
  log "claude-mem already installed — skipping."
fi

# Start the worker explicitly. The installer skips auto-start in non-TTY mode,
# so do it here unconditionally — idempotent (no-op if already running).
as_user 'mise exec node -- npx --yes claude-mem start </dev/null' || \
  warn "claude-mem worker failed to start — run 'npx claude-mem start' manually after first login."
