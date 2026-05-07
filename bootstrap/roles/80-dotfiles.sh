#!/usr/bin/env bash
# Role 80: Deploy dotfiles via yadm for the interactive user.
# Runs after all system packages and runtimes are installed (role 60).
# Requires: yadm (role 40), git (role 40), openssh-client (role 00/system).
#
# Two clone paths — pick whichever fits your workflow:
#
#   SSH (default)    Generate a key, add the printed pubkey to GitHub once,
#                    then re-run: sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles
#
#   HTTPS (no re-run) Export DOTFILES_TOKEN=<github-pat> before running.
#                    The PAT needs repo read scope (or "contents: read" for
#                    fine-grained tokens).  No SSH key needed; no re-run.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

HOME_DIR="/home/$USERNAME"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:LuisMedinaG/.dotfiles.git}"
SSH_KEY="$HOME_DIR/.ssh/id_ed25519"
RERUN_CMD="sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles"

# ── Shared helpers ───────────────────────────────────────────────────────────

_clone_dotfiles() {
  # Call yadm directly (no bash -lc) to avoid shell-injection via DOTFILES_REPO.
  # --no-bootstrap: we run bootstrap explicitly below; avoid an interactive
  # prompt or a double-run if yadm.bootstrap-after-clone is set in the repo.
  sudo -u "$USERNAME" -H yadm clone --no-bootstrap -- "$1"
}

_run_yadm_bootstrap() {
  if as_user 'yadm bootstrap'; then
    log "Dotfiles bootstrap complete."
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

# ── Path 1: HTTPS clone via Personal Access Token (zero re-run) ─────────────
if [[ -n "${DOTFILES_TOKEN:-}" ]]; then
  log "DOTFILES_TOKEN set — cloning via HTTPS (no SSH key needed)."

  # Convert git@github.com:owner/repo.git → https://github.com/owner/repo.git
  HTTPS_REPO="${DOTFILES_REPO/git@github.com:/https://github.com/}"

  # Write the PAT to the user's .netrc so it is never visible in argv or the
  # process environment (which `ps` can expose).  Back up any existing .netrc
  # and restore it on exit — even if this script aborts midway.
  NETRC_FILE="$HOME_DIR/.netrc"
  NETRC_BACKUP="$HOME_DIR/.netrc.bootstrap-bak"
  _cleanup_netrc() {
    rm -f "$NETRC_FILE"
    [[ -f "$NETRC_BACKUP" ]] && mv "$NETRC_BACKUP" "$NETRC_FILE" || true
  }
  trap '_cleanup_netrc' EXIT INT TERM

  [[ -f "$NETRC_FILE" ]] && cp "$NETRC_FILE" "$NETRC_BACKUP"
  install -m 600 -o "$USERNAME" -g "$USERNAME" /dev/null "$NETRC_FILE"
  printf 'machine github.com login x-access-token password %s\n' "$DOTFILES_TOKEN" >"$NETRC_FILE"

  # GIT_TERMINAL_PROMPT=0 prevents git from falling back to an interactive
  # credential prompt if .netrc auth fails (e.g. bad token).
  if sudo -u "$USERNAME" -H env GIT_TERMINAL_PROMPT=0 \
       yadm clone --no-bootstrap -- "$HTTPS_REPO"; then
    log "Dotfiles cloned successfully."
  else
    die "HTTPS clone failed — verify DOTFILES_TOKEN has repo read access and DOTFILES_REPO is correct."
  fi

  _run_yadm_bootstrap
  exit 0
fi

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
else
  warn "yadm clone failed — verify SSH access, then re-run: $RERUN_CMD"
  exit 0
fi

_run_yadm_bootstrap
