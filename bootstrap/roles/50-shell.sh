#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="/home/$USERNAME"
ZSH_BIN="$(command -v zsh)"
if [[ "$(getent passwd "$USERNAME" | cut -d: -f7)" != "$ZSH_BIN" ]]; then
  chsh -s "$ZSH_BIN" "$USERNAME"
fi

if ! command -v starship >/dev/null 2>&1; then
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
fi

install -m 644 -o "$USERNAME" -g "$USERNAME" \
  "$SCRIPT_DIR/config/tmux.conf" "$HOME_DIR/.tmux.conf"

ZSHRC="$HOME_DIR/.zshrc"
if [[ ! -f "$ZSHRC" ]]; then
  install -m 644 -o "$USERNAME" -g "$USERNAME" /dev/null "$ZSHRC"
fi
ensure_line 'eval "$(starship init zsh)"' "$ZSHRC"
ensure_line 'export PATH="$HOME/.local/bin:$PATH"' "$ZSHRC"
ensure_line '[[ -f "$HOME/.fnm/fnm" ]] && eval "$($HOME/.fnm/fnm env --use-on-cd)"' "$ZSHRC"
ensure_line '[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"' "$ZSHRC"
ensure_line '[[ -d "/usr/local/go/bin" ]] && export PATH="/usr/local/go/bin:$PATH"' "$ZSHRC"
chown "$USERNAME":"$USERNAME" "$ZSHRC"
