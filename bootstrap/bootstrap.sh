#!/usr/bin/env bash
# Run as root on a fresh Ubuntu 24.04 host.
#   sudo USERNAME=luis ./bootstrap.sh
#   sudo USERNAME=luis ./bootstrap.sh 40-dev-tools 60-langs   # subset
set -euo pipefail

: "${USERNAME:=luis}"
: "${TIMEZONE:=America/Mexico_City}"
: "${TS_AUTHKEY:=}"               # optional, prefills tailscale auth — NOT exported globally
: "${SKIP_FIREWALL:=${SKIP_UFW:-0}}"  # set to 1 to skip ufw only; fail2ban + sshd hardening still run
: "${USER_PASSWORD:=}"            # optional — if set, role 10 runs chpasswd; otherwise set manually
# TS_AUTHKEY and USER_PASSWORD are intentionally excluded from this export list.
# Each is passed inline only to its consuming role to keep secrets out of all
# other child process environments.
USER_HOME="/home/$USERNAME"
export USERNAME TIMEZONE SKIP_FIREWALL USER_HOME

# Capture before the loop — USER_PASSWORD is unset after role 10 runs.
[[ -n "$USER_PASSWORD" ]] && _passwd_provided=1 || _passwd_provided=""

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
  43-caddy        # Caddy reverse proxy — HTTP/HTTPS foundation for services
  50-shell
  60-langs
  70-claude-code  # npm install -g @anthropic-ai/claude-code
  80-dotfiles     # yadm clone + bootstrap (runs as $USERNAME, requires GitHub SSH)
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
    TS_AUTHKEY="$TS_AUTHKEY" env -u USER_PASSWORD bash "$SCRIPT_DIR/roles/${role}.sh"
    unset TS_AUTHKEY
  elif [[ "$role" == "10-user" ]]; then
    # Pass USER_PASSWORD only to role 10; unset after so it doesn't leak further.
    USER_PASSWORD="$USER_PASSWORD" env -u TS_AUTHKEY bash "$SCRIPT_DIR/roles/${role}.sh"
    unset USER_PASSWORD
  else
    # Belt-and-suspenders: strip both secrets from every other child.
    env -u TS_AUTHKEY -u USER_PASSWORD bash "$SCRIPT_DIR/roles/${role}.sh"
  fi
done

log "Bootstrap complete."

NEEDS_REBOOT=""
NEEDS_DOTFILES=""
NEEDS_TAILSCALE=""

# Check for kernel updates requiring reboot.
if [[ -f /var/run/reboot-required ]]; then
  NEEDS_REBOOT=1
fi

# Check if dotfiles were cloned. If not, instruct to scp the private key and re-run.
if ! as_user '[[ -d "$HOME/.local/share/yadm/repo.git" ]]' 2>/dev/null; then
  NEEDS_DOTFILES=1
fi

# Check if Tailscale was enrolled. If not, instruct manual connect.
if ! tailscale status >/dev/null 2>&1; then
  NEEDS_TAILSCALE=1
fi

log ""
log "=== NEXT STEPS ==="
log ""

STEP=0

if [[ -n "$NEEDS_REBOOT" ]]; then
  (( ++STEP ))
  log "${STEP}. REBOOT (kernel updates applied):"
  log "   reboot"
  log ""
fi

if [[ -n "$NEEDS_TAILSCALE" ]]; then
  (( ++STEP ))
  log "${STEP}. CONNECT TAILSCALE:"
  log "   sudo tailscale up --ssh --hostname devbox --advertise-tags=tag:devbox"
  log ""
fi

if [[ -n "$NEEDS_DOTFILES" ]]; then
  (( ++STEP ))
  log "${STEP}. DEPLOY DOTFILES (recommended — no re-run required):"
  log "   sudo DOTFILES_TOKEN=<github-pat> bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles"
  log ""
  log "   SSH fallback — add the key role 80 printed above to GitHub, then:"
  log "   sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles"
  log ""
fi

if [[ -z "$_passwd_provided" ]]; then
  log "SET A PASSWORD for $USERNAME (required for sudo):"
  log "   passwd $USERNAME"
  log ""
fi
log "Reconnect after reboot: tailscale ssh $USERNAME@devbox"
log "Or via Tailscale IP:    ssh $USERNAME@<ip-from-tailscale-status>"
