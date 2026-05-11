#!/usr/bin/env bash
# Shared helpers. All idempotency primitives live here.
set -euo pipefail

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# Append a line to a file only if it isn't already present.
ensure_line() {
  local line="$1" file="$2"
  grep -qxF -- "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Load pinned versions from config/versions.conf (idempotent across roles).
source_versions() {
  [[ -n "${_VERSIONS_SOURCED:-}" ]] && return
  local conf="$SCRIPT_DIR/config/versions.conf"
  [[ -f "$conf" ]] || die "config/versions.conf not found."
  # shellcheck source=/dev/null
  source "$conf"
  _VERSIONS_SOURCED=1
}

# Detect host architecture. Sets ARCH (short) and ARCH_FULL (dpkg-native).
# Optionally resolves and validates arch-specific SHA256 for a tool prefix.
#   detect_arch              # sets ARCH, ARCH_FULL
#   detect_arch OLLAMA       # also exports OLLAMA_SHA256, validates OLLAMA_VERSION + _SHA256_*
detect_arch() {
  ARCH_FULL="$(dpkg --print-architecture)"
  case "$ARCH_FULL" in
    amd64) ARCH=x64 ;;
    arm64) ARCH=arm64 ;;
    *) die "Unsupported architecture: $ARCH_FULL" ;;
  esac

  local prefix="${1:-}"
  [[ -z "$prefix" ]] && return

  local sha256_var="${prefix}_SHA256_${ARCH_FULL^^}"
  [[ -n "${!sha256_var:-}" ]] || die "${sha256_var} is empty — add to config/versions.conf"
  printf -v "${prefix}_SHA256" '%s' "${!sha256_var}"
  export "${prefix}_SHA256"

  local version_var="${prefix}_VERSION"
  [[ -n "${!version_var:-}" ]] || die "${version_var} is empty — add to config/versions.conf"
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
  sudo -u "$USERNAME" -H bash -lc "cd ~ && $*"
}

make_user_dir() {
  install -d -m 755 -o "$USERNAME" -g "$USERNAME" "$@"
}

enable_service() {
  systemctl enable --now "$1"
}

reload_sshd() {
  # Ubuntu 24.04 ships sshd as socket-activated (ssh.socket): ssh.service only
  # runs while a connection is open and is otherwise inactive. A `reload` on
  # an inactive unit returns non-zero, which would abort bootstrap under
  # `set -e`. Skipping the reload is safe — each socket-spawned sshd re-reads
  # /etc/ssh/sshd_config.d/* on connect.
  if systemctl is-active --quiet ssh; then
    systemctl reload ssh
  fi
}

# Download a URL to a destination path and verify its sha256 checksum.
# Aborts if the expected hash is empty or does not match.
# Skips the download if the file already exists and the hash already matches
# (makes re-runs faster without sacrificing integrity).
#   download_verify <url> <dest> <expected_sha256>
download_verify() {
  local url="$1" dest="$2" expected="$3"
  [[ -n "$expected" ]] || die "download_verify: no sha256 provided for $url — refusing to download unverified."
  if [[ -f "$dest" ]] && echo "${expected}  ${dest}" | sha256sum -c - >/dev/null 2>&1; then
    return 0
  fi
  curl -fsSL "$url" -o "$dest"
  echo "${expected}  ${dest}" | sha256sum -c - \
    || die "sha256 mismatch for $dest (url: $url). Aborting."
}
