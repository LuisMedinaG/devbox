#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="$USER_HOME"

# bootstrap.SHELL.1
ZSH_BIN="$(command -v zsh)"
if [[ "$(getent passwd "$USERNAME" | cut -d: -f7)" != "$ZSH_BIN" ]]; then
  chsh -s "$ZSH_BIN" "$USERNAME"
fi

# Create an empty .zshrc so yadm clone has a file to replace.
# Do NOT write config here — dotfiles own .zshrc.
# bootstrap.SHELL.2
ZSHRC="$HOME_DIR/.zshrc"
if [[ ! -f "$ZSHRC" ]]; then
  install -m 644 -o "$USERNAME" -g "$USERNAME" /dev/null "$ZSHRC"
fi

# Machine-specific PATH entries go in .zshrc.local (not tracked by yadm).
# .zshrc sources this file at the bottom, so these survive yadm clone.
# bootstrap.SHELL.3
ZSHRC_LOCAL="$HOME_DIR/.zshrc.local"
ensure_line 'export PATH="$HOME/.local/bin:$PATH"' "$ZSHRC_LOCAL"
ensure_line '[[ -f "$HOME/.fnm/fnm" ]] && eval "$($HOME/.fnm/fnm env --use-on-cd)"' "$ZSHRC_LOCAL"
ensure_line '[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"' "$ZSHRC_LOCAL"
ensure_line '[[ -d "/usr/local/go/bin" ]] && export PATH="/usr/local/go/bin:$PATH"' "$ZSHRC_LOCAL"
chown "$USERNAME":"$USERNAME" "$ZSHRC_LOCAL"
