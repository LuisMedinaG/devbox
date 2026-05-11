#!/usr/bin/env bash
# Role 80: Deploy dotfiles via yadm for the interactive user.
# Runs after all system packages and runtimes are installed (role 60).
# Requires: yadm (role 40), git (role 40), openssh-client (role 00/system).
#
# Two clone paths — pick whichever fits your workflow:
#
#   HTTPS (default)  Works for public repos — no credentials needed.
#
#   SSH (fallback)   Generate a key, add the printed pubkey to GitHub once,
#                    then re-run: sudo bash ~/projects/devbox/bootstrap.sh 80-dotfiles
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="$USER_HOME"
SSH_KEY="$HOME_DIR/.ssh/id_ed25519"

if [[ -z "${DOTFILES_REPO:-}" ]]; then
  warn "DOTFILES_REPO not set — skipping dotfiles clone."
  warn "To deploy dotfiles, re-run with:"
  warn "  sudo DOTFILES_REPO=git@github.com:<owner>/.dotfiles.git \\"
  warn "       ./bootstrap.sh 80-dotfiles"
  exit 0
fi
RERUN_CMD="sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles"

# ── Shared helpers ───────────────────────────────────────────────────────────

_clone_dotfiles() {
  # Call yadm directly (no bash -lc) to avoid shell-injection via DOTFILES_REPO.
  # --no-bootstrap: we run bootstrap explicitly below; avoid an interactive
  # prompt or a double-run if yadm.bootstrap-after-clone is set in the repo.
  sudo -u "$USERNAME" -H env GIT_TERMINAL_PROMPT=0 yadm clone --no-bootstrap -- "$1"
}

# Earlier roles (e.g. 50-shell) drop placeholder files in $HOME like an empty
# .zshrc. yadm clone leaves these alone and reports them as local differences,
# which then makes `yadm pull --rebase` (run by the dotfiles bootstrap script)
# fail with "cannot pull with rebase: You have unstaged changes". For a fresh
# provision the dotfiles version always wins, so force-overwrite them here.
_reset_local_diffs() {
  as_user 'yadm checkout -- "$HOME" 2>/dev/null || true'
  as_user 'yadm reset --hard HEAD >/dev/null 2>&1 || true'
}

_run_yadm_bootstrap() {
  # yadm refuses to run the bootstrap script unless it's executable.
  # The dotfiles repo may track it without the +x bit, so ensure it here.
  as_user '[[ -f "$HOME/.config/yadm/bootstrap" ]] && chmod +x "$HOME/.config/yadm/bootstrap"' || true

  # DOTFILES_PROFILE: pick which yadm bootstrap profile to run. Default
  # "linuxbox" is correct for the Hetzner devbox. The value is exported AND
  # piped as a numeric menu choice so it works against two styles of dotfiles
  # bootstrap script:
  #   1. Scripts that read $DOTFILES_PROFILE directly (preferred — the env
  #      var is already in the environment).
  #   2. Scripts that prompt interactively with "Profile [1/2/3]:" — the
  #      menu_choice number is piped on stdin.
  : "${DOTFILES_PROFILE:=linuxbox}"
  local menu_choice
  case "$DOTFILES_PROFILE" in
    personal) menu_choice=1 ;;
    work)     menu_choice=2 ;;
    linuxbox) menu_choice=3 ;;
    *) die "Unknown DOTFILES_PROFILE: $DOTFILES_PROFILE (expected personal|work|linuxbox)" ;;
  esac

  if as_user "DOTFILES_PROFILE='$DOTFILES_PROFILE' bash -lc 'echo $menu_choice | yadm bootstrap'"; then
    log "Dotfiles bootstrap complete (profile: $DOTFILES_PROFILE)."
  else
    warn "yadm bootstrap had errors — review output above."
  fi
}

# ── Idempotency guard ────────────────────────────────────────────────────────
if as_user '[[ -d "$HOME/.local/share/yadm/repo.git" ]]'; then
  log "Dotfiles already cloned — pulling latest ..."
  as_user 'yadm pull' || warn "yadm pull failed — check connectivity or conflicts."
  _run_yadm_bootstrap
  exit 0
fi

# ── Path 1: HTTPS clone (public repo, no credentials needed) ─────────────────
HTTPS_REPO="${DOTFILES_REPO/git@github.com:/https://github.com/}"
log "Cloning dotfiles via HTTPS ..."
if sudo -u "$USERNAME" -H env GIT_TERMINAL_PROMPT=0 \
     yadm clone --no-bootstrap -- "$HTTPS_REPO" 2>/dev/null; then
  log "Dotfiles cloned successfully."
  _reset_local_diffs
  _run_yadm_bootstrap
  exit 0
fi
warn "HTTPS clone failed — repo may be private. Falling back to SSH."

# ── Path 2: SSH clone ────────────────────────────────────────────────────────

# Generate SSH key if absent.
if [[ ! -f "$SSH_KEY" ]]; then
  log "Generating SSH key for $USERNAME ..."
  sudo -u "$USERNAME" -H ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "${USERNAME}@devbox"
fi

# Always print the key and instructions until a successful clone — makes
# re-runs self-contained even if the user lost the original output.
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Add this public key to GitHub (one-time):"
log ""
log "  $(cat "$SSH_KEY.pub")"
log ""
log "  1. Go to: https://github.com/settings/ssh/new"
log "  2. Paste the key and save"
log "  3. Re-run:  $RERUN_CMD"
log ""
log "  Zero re-run alternative: export DOTFILES_TOKEN=<pat> and re-run"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""

# Pre-check SSH connectivity before the clone to surface auth errors fast
# rather than waiting for git's default SSH timeout.
#   StrictHostKeyChecking=accept-new  — trust new host keys but not changed ones
#   BatchMode=yes                     — no interactive password/keyboard prompt
#   ConnectTimeout=10                 — fail fast instead of hanging
log "Testing GitHub SSH connectivity (timeout 10 s) ..."
SSH_OUT=$(sudo -u "$USERNAME" -H \
  ssh -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      -T git@github.com 2>&1 || true)

if ! printf '%s' "$SSH_OUT" | grep -q "successfully authenticated"; then
  warn "GitHub SSH authentication failed — key not yet added or network issue."
  warn "Add the key above, then re-run: $RERUN_CMD"
  exit 0
fi

log "GitHub SSH: OK"

if _clone_dotfiles "$DOTFILES_REPO"; then
  log "Dotfiles cloned successfully."
  _reset_local_diffs
else
  warn "yadm clone failed — verify SSH access, then re-run: $RERUN_CMD"
  exit 0
fi

_run_yadm_bootstrap
