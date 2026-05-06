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

log "Bootstrap complete. SSH in as $USERNAME and run user-level setup."

# If a kernel update was installed during bootstrap, a reboot is required.
if [[ -f /var/run/reboot-required ]]; then
  log ""
  log "*** System restart required ***"
  log "Kernel security updates were applied. Reboot now: reboot"
  log "Then reconnect via: tailscale ssh $USERNAME@devbox"
fi
