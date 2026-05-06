#!/usr/bin/env bash
# Run as root on a fresh Ubuntu 24.04 host.
#   sudo USERNAME=luis ./bootstrap.sh
#   sudo USERNAME=luis ./bootstrap.sh 40-dev-tools 60-langs   # subset
set -euo pipefail

: "${USERNAME:=luis}"
: "${TIMEZONE:=America/Mexico_City}"
: "${TS_AUTHKEY:=}"               # optional, prefills tailscale auth — NOT exported globally
: "${SKIP_FIREWALL:=${SKIP_UFW:-0}}"  # set to 1 to skip ufw only; fail2ban + sshd hardening still run
# TS_AUTHKEY is intentionally excluded from this export list — it's passed
# inline only to role 30-tailscale below to keep the secret out of the env
# of every other role's child bash process.
export USERNAME TIMEZONE SKIP_FIREWALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
  die "Must run as root for initial bootstrap."
fi

LOG_DIR="/var/log/bootstrap"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Logging to $LOG_FILE"

ROLES=(
  00-system
  10-user
  20-hardening    # sshd config + fail2ban only — no UFW, public SSH stays open
  30-tailscale    # connect Tailscale overlay
  31-firewall     # UFW — runs after Tailscale so port 22 is never closed prematurely
  40-dev-tools
  42-docker       # rootless Podman
  50-shell
  60-langs
  70-dotfiles     # yadm clone + bootstrap (runs as $USERNAME, requires GitHub SSH)
)

if [[ $# -gt 0 ]]; then
  ROLES=("$@")
fi

for role in "${ROLES[@]}"; do
  log "==> Running role: $role"
  if [[ "$role" == "30-tailscale" ]]; then
    # Pass TS_AUTHKEY only to this role's child bash; scrub from parent
    # immediately after so any later role (or a re-ordered subset run
    # like `bootstrap.sh 60-langs 30-tailscale`) cannot inherit it.
    TS_AUTHKEY="$TS_AUTHKEY" bash "$SCRIPT_DIR/roles/${role}.sh"
    unset TS_AUTHKEY
  else
    # Belt-and-suspenders: explicitly strip TS_AUTHKEY from each child's
    # env so any callers that exported it before invoking bootstrap.sh
    # cannot leak it into roles other than 30-tailscale.
    env -u TS_AUTHKEY bash "$SCRIPT_DIR/roles/${role}.sh"
  fi
done

log "Bootstrap complete."

NEEDS_REBOOT=""
NEEDS_DOTFILES=""
NEEDS_TAILSCALE=""
NEEDS_CC=""

# Check for kernel updates requiring reboot.
if [[ -f /var/run/reboot-required ]]; then
  NEEDS_REBOOT=1
fi

# Check if dotfiles were cloned. If not, instruct to scp the private key and re-run.
HOME_DIR="/home/$USERNAME"
if ! as_user '[[ -d "$HOME/.local/share/yadm/repo.git" ]]' 2>/dev/null; then
  NEEDS_DOTFILES=1
fi

# Check if Tailscale was enrolled. If not, instruct manual connect.
if ! tailscale status >/dev/null 2>&1; then
  NEEDS_TAILSCALE=1
fi

# Check if Claude Code is installed.
if ! as_user 'command -v claude >/dev/null 2>&1' 2>/dev/null; then
  NEEDS_CC=1
fi

log ""
log "=== NEXT STEPS ==="
log ""

if [[ -n "$NEEDS_REBOOT" ]]; then
  log "1. REBOOT (kernel updates applied, restart required):"
  log "   reboot"
  log ""
fi

if [[ -n "$NEEDS_TAILSCALE" ]]; then
  log "2. CONNECT TAILSCALE (if you didn't pass TS_AUTHKEY):"
  log "   sudo tailscale up --ssh --hostname devbox --advertise-tags=tag:devbox"
  log ""
fi

if [[ -n "$NEEDS_DOTFILES" ]]; then
  log "3. DEPLOY DOTFILES — copy your private SSH key, then re-run:"
  log "   # From your Mac:"
  log "   scp ~/.ssh/id_ed25519 $USERNAME@$(hostname -I | awk '{print $1}'):~/.ssh/"
  log "   # On this host:"
  log "   sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 70-dotfiles"
  log ""
fi

if [[ -n "$NEEDS_CC" ]]; then
  log "4. INSTALL CLAUDE CODE:"
  log "   npm install -g @anthropic-ai/claude-code"
  log ""
fi

log "Reconnect after reboot: tailscale ssh $USERNAME@devbox"
log "Or via Tailscale IP:    ssh $USERNAME@<ip-from-tailscale-status>"
