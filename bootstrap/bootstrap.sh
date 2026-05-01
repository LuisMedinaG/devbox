#!/usr/bin/env bash
# Run as root on a fresh Ubuntu 24.04 host.
#   sudo USERNAME=luis ./bootstrap.sh
#   sudo USERNAME=luis ./bootstrap.sh 40-dev-tools 60-langs   # subset
set -euo pipefail

: "${USERNAME:=luis}"
: "${TIMEZONE:=America/Mexico_City}"
: "${TS_AUTHKEY:=}"   # optional, prefills tailscale auth
export USERNAME TIMEZONE TS_AUTHKEY

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
  die "Must run as root for initial bootstrap."
fi

ROLES=(
  00-system
  10-user
  20-hardening
  30-tailscale
  40-dev-tools
  50-shell
  60-langs
  70-claude-code
  80-docker
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
