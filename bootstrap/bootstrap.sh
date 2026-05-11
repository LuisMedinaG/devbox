#!/usr/bin/env bash
# Run as root on a fresh Ubuntu 24.04 host.
#   USERNAME=alice bash bootstrap.sh                     # direct root execution
#   sudo USERNAME=alice ./bootstrap.sh 40-dev-tools     # via sudo (SUDO_USER also accepted)
set -euo pipefail

# Prefer explicit USERNAME; fall back to SUDO_USER (set by sudo); die if neither.
: "${USERNAME:=${SUDO_USER:-}}"
[[ -n "$USERNAME" ]] || { printf '[fail] USERNAME is not set. Run as: USERNAME=<user> bash bootstrap.sh\n' >&2; exit 1; }
: "${TIMEZONE:=America/Mexico_City}"
: "${MACHINE_NAME:=devbox}"        # tailnet hostname + sshd identity (role 30)
: "${TS_TAG:=tag:${MACHINE_NAME}}" # tailscale ACL tag (role 30)
: "${TS_AUTHKEY:=}"                # optional, prefills tailscale auth — NOT exported globally
: "${DEV_MODE:=0}"                 # 1 = keep public SSH usable during dev iteration (sets SKIP_* below)
: "${SKIP_FIREWALL:=${SKIP_UFW:-0}}"      # 1 = skip ufw only; fail2ban + sshd hardening still run
: "${SKIP_SSH_HARDENING:=0}"       # 1 = skip role 20's sshd drop-in; fail2ban still runs
: "${USER_PASSWORD:=}"             # optional — if set, role 10 runs chpasswd; otherwise set manually

# DEV_MODE is an umbrella: implies SKIP_FIREWALL=1 and SKIP_SSH_HARDENING=1.
# Use only while iterating on bootstrap from a Mac that can't reach the box
# over Tailscale yet. NEVER leave on for a long-lived host.
if [[ "$DEV_MODE" = "1" ]]; then
  SKIP_FIREWALL=1
  SKIP_SSH_HARDENING=1
  printf '[warn] DEV_MODE=1 — sshd hardening and UFW are SKIPPED. Do not use in production.\n' >&2
fi
# TS_AUTHKEY and USER_PASSWORD are intentionally excluded from this export list.
# Each is passed inline only to its consuming role to keep secrets out of all
# other child process environments.
USER_HOME="/home/$USERNAME"
export USERNAME TIMEZONE MACHINE_NAME TS_TAG SKIP_FIREWALL SKIP_SSH_HARDENING DEV_MODE USER_HOME

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

# ── Role cache (Docker-style layer skipping) ─────────────────────────────────
# Active only for full default runs (no explicit role args).
# Hash covers the role script, common.sh, and role-specific skip flags so that
# changing flag values (e.g. DEV_MODE=1 → production) invalidates the cache.
# A role's cache is written only after it exits 0 — failed roles always re-run.
CACHE_DIR="/var/lib/bootstrap/cache"
mkdir -p "$CACHE_DIR"

_role_hash() {
  local hash_input
  hash_input="$(cat "$SCRIPT_DIR/roles/${1}.sh" "$SCRIPT_DIR/lib/common.sh")"
  # Include skip flags in the hash so changing flag values invalidates the cache.
  # This prevents a DEV_MODE=1 run from caching a role that should re-run in production.
  case "$1" in
    20-hardening) hash_input+="${SKIP_SSH_HARDENING:-0}" ;;
    31-firewall)  hash_input+="${SKIP_FIREWALL:-0}" ;;
  esac
  printf '%s' "$hash_input" | sha256sum | cut -d' ' -f1
}
_role_cached()      { local c="$CACHE_DIR/${1}.sha256"; [[ -f "$c" ]] && [[ "$(cat "$c")" = "$(_role_hash "$1")" ]]; }
_role_cache_write() { _role_hash "$1" > "$CACHE_DIR/${1}.sha256"; }

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

# Cache is disabled when explicit roles are passed — those always run unconditionally.
[[ $# -gt 0 ]] && _CACHE_ENABLED=0 || _CACHE_ENABLED=1

if [[ $# -gt 0 ]]; then
  ROLES=("$@")
fi

for role in "${ROLES[@]}"; do
  if [[ "$_CACHE_ENABLED" -eq 1 ]] && _role_cached "$role"; then
    log "==> Skipping role: $role (unchanged since last run)"
    continue
  fi

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

  [[ "$_CACHE_ENABLED" -eq 1 ]] && _role_cache_write "$role"
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
  log "   sudo tailscale up --ssh --hostname $MACHINE_NAME --advertise-tags=$TS_TAG"
  log ""
fi

if [[ -n "$NEEDS_DOTFILES" ]]; then
  (( ++STEP ))
  log "${STEP}. DEPLOY DOTFILES:"
  log "   sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles"
  log ""
  log "   If the public HTTPS clone fails, add the SSH key role 80 printed"
  log "   above to GitHub and re-run the same command."
  log ""
fi

if [[ -z "$_passwd_provided" ]]; then
  (( ++STEP ))
  log "${STEP}. SET A PASSWORD for $USERNAME (required for sudo):"
  log "   passwd $USERNAME"
  log ""
fi
log "Reconnect after reboot: tailscale ssh $USERNAME@$MACHINE_NAME"
log "Or via Tailscale IP:    ssh $USERNAME@<ip-from-tailscale-status>"
