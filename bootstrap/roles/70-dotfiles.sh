#!/usr/bin/env bash
# Role 70: Deploy dotfiles via yadm for the interactive user.
# Runs after all system packages and runtimes are installed (role 60).
# Requires: yadm (role 40), SSH keys (role 10), git (role 40).
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="/home/$USERNAME"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:LuisMedinaG/.dotfiles.git}"

# Skip if dotfiles already cloned (yadm stores its git dir under .local/share/yadm).
if as_user '[[ -d "$HOME/.local/share/yadm/repo.git" ]]'; then
  log "Dotfiles already cloned — skipping."
  exit 0
fi

# Clone via yadm. Requires the user's SSH key to be configured for GitHub.
if as_user "yadm clone ${DOTFILES_REPO}"; then
  log "Dotfiles cloned successfully."
else
  warn "yadm clone failed — luis needs a private SSH key to clone from GitHub."
  warn "Run on your Mac:  scp ~/.ssh/id_ed25519 $USERNAME@$(hostname -I | awk '{print $1}'):~/.ssh/"
  warn "Then on this host: sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 70-dotfiles"
  exit 0
fi

# Run dotfiles bootstrap (installs Homebrew packages, configures tools).
if as_user 'yadm bootstrap'; then
  log "Dotfiles bootstrap complete."
else
  warn "yadm bootstrap had errors — review output above."
fi
