#!/usr/bin/env bash
# Role 70: Deploy dotfiles via yadm for the interactive user.
# Runs after all system packages and runtimes are installed (role 60).
# Requires: yadm (role 40), git (role 40).
#
# If luis has no SSH key, generates one and instructs the user to add the
# public key to GitHub. No need to scp a private key from your Mac.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="/home/$USERNAME"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:LuisMedinaG/.dotfiles.git}"
SSH_KEY="$HOME_DIR/.ssh/id_ed25519"

# Skip if dotfiles already cloned.
if as_user '[[ -d "$HOME/.local/share/yadm/repo.git" ]]'; then
  log "Dotfiles already cloned — skipping."
  exit 0
fi

# Generate SSH key for the user if one doesn't exist.
if [[ ! -f "$SSH_KEY" ]]; then
  log "Generating SSH key for $USERNAME ..."
  sudo -u "$USERNAME" -H ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "${USERNAME}@devbox"
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  ADD THIS PUBLIC KEY TO GITHUB:"
  log ""
  cat "$SSH_KEY.pub"
  log ""
  log "  1. Copy the key above"
  log "  2. Go to: https://github.com/settings/ssh/new"
  log "  3. Paste it and save"
  log "  4. Then re-run: sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 70-dotfiles"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
  exit 0
fi

# Try cloning dotfiles via yadm.
if as_user "yadm clone ${DOTFILES_REPO}"; then
  log "Dotfiles cloned successfully."
else
  warn "yadm clone failed — is the public key added to GitHub?"
  warn "Check: https://github.com/settings/keys"
  warn "Then re-run: sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 70-dotfiles"
  exit 0
fi

# Run dotfiles bootstrap.
if as_user 'yadm bootstrap'; then
  log "Dotfiles bootstrap complete."
else
  warn "yadm bootstrap had errors — review output above."
fi
