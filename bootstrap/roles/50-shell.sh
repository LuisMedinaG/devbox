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
ensure_line 'eval "$(mise activate zsh)"' "$ZSHRC_LOCAL"
chown "$USERNAME":"$USERNAME" "$ZSHRC_LOCAL"

# bootstrap.SHELL.4 — minimal zsh for root (no plugins, no mise, no user paths)
ROOT_ZSH="$(command -v zsh)"
if [[ "$(getent passwd root | cut -d: -f7)" != "$ROOT_ZSH" ]]; then
  chsh -s "$ROOT_ZSH" root
fi

cat >/root/.zshrc <<'EOF'
# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Prompt: user@host path #
autoload -Uz promptinit && promptinit
PS1='%F{red}%n@%m%f %F{cyan}%~%f %# '

# Aliases (guarded — tools may not be installed)
command -v eza  >/dev/null 2>&1 && alias ls='eza --group-directories-first'
command -v nvim >/dev/null 2>&1 && alias vim='nvim' && alias vi='nvim'
alias ll='ls -lah'
EOF
