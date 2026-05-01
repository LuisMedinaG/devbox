#!/usr/bin/env bash
# Shared helpers. All idempotency primitives live here.
set -euo pipefail

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# Run only if a marker file is missing.
once() {
  local name="$1"; shift
  local marker="/var/lib/bootstrap/${name}.done"
  mkdir -p /var/lib/bootstrap
  if [[ -f "$marker" ]]; then
    log "skip: $name (already done)"
    return 0
  fi
  "$@"
  touch "$marker"
}

# Append a line to a file only if it isn't already present.
ensure_line() {
  local line="$1" file="$2"
  grep -qxF -- "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Replace or append a `key value` style directive in a config file.
ensure_kv() {
  local key="$1" value="$2" file="$3" sep="${4:- }"
  if grep -Eq "^[#[:space:]]*${key}\b" "$file" 2>/dev/null; then
    sed -i -E "s|^[#[:space:]]*(${key})\b.*|\1${sep}${value}|" "$file"
  else
    echo "${key}${sep}${value}" >> "$file"
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  if [[ ! -f /var/lib/bootstrap/apt-updated ]] \
     || [[ -n $(find /var/lib/bootstrap/apt-updated -mmin +60 2>/dev/null) ]]; then
    apt-get update -y
    mkdir -p /var/lib/bootstrap && touch /var/lib/bootstrap/apt-updated
  fi
}

as_user() {
  sudo -u "$USERNAME" -H bash -lc "$*"
}

# Returns 0 if systemd is PID 1 (Hetzner/VPS), 1 if not (Fly, containers).
have_systemd() {
  [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]
}

# Enable + start a system service.
# On systemd hosts: systemctl enable --now.
# On non-systemd hosts (Fly): start the binary directly; /start.sh handles future boots.
enable_service() {
  local name="$1" bin="${2:-}"
  if have_systemd; then
    systemctl enable --now "$name"
  elif [ -n "$bin" ] && [ -x "$bin" ]; then
    "$bin" &
    log "started $name directly (no systemd; /start.sh handles reboots)"
  else
    warn "$name: systemd unavailable and no fallback binary — will start on next boot via /start.sh"
  fi
}

# Reload sshd config.
reload_sshd() {
  if have_systemd; then
    systemctl reload ssh
  elif [ -f /var/run/sshd.pid ]; then
    kill -HUP "$(cat /var/run/sshd.pid)"
  fi
}
