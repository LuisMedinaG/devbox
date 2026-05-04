#!/usr/bin/env bash
# Run as root on a fresh Ubuntu 24.04 host.
#   sudo USERNAME=luis ./bootstrap.sh
#   sudo USERNAME=luis ./bootstrap.sh 40-dev-tools 60-langs   # subset
set -euo pipefail

: "${USERNAME:=luis}"
: "${ADMIN_USERNAME:=$USERNAME}"  # separate admin account; defaults to USERNAME for dev boxes
: "${AGENT_USER:=agent}"          # dedicated sandbox user, no sudo
: "${TIMEZONE:=America/Mexico_City}"
: "${TS_AUTHKEY:=}"               # optional, prefills tailscale auth
: "${SKIP_FIREWALL:=${SKIP_UFW:-0}}"  # set to 1 to skip ufw + fail2ban (sshd hardening still runs)
: "${INSTALL_DOCKER:=0}"          # set to 1 to install rootful Docker alongside Podman
: "${GPU_PROFILE:=consumer}"      # none | consumer | datacenter
export USERNAME ADMIN_USERNAME AGENT_USER TIMEZONE TS_AUTHKEY SKIP_FIREWALL INSTALL_DOCKER GPU_PROFILE

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
  20-hardening
  30-tailscale
  35-gpu          # NVIDIA driver + CDI (no-op on CPU hosts)
  40-dev-tools
  42-docker       # rootless Podman config + optional hardened Docker
  45-agent-sandbox  # rootless Podman + agent system user (no sudo)
  50-shell
  60-langs
  70-claude-code  # builds agent container image; no host claude binary
  90-backups
)

if [[ $# -gt 0 ]]; then
  ROLES=("$@")
fi

for role in "${ROLES[@]}"; do
  log "==> Running role: $role"
  bash "$SCRIPT_DIR/roles/${role}.sh"
done

log "Bootstrap complete. SSH in as $USERNAME and run user-level setup."
