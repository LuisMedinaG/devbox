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

# Replace or append a `key value` style directive in a config file.
# Uses \x01 as the sed delimiter so values containing |, /, # etc. are safe.
# Escapes both sed-replacement specials (\, &) and shell-quote-sensitive
# characters ($, `, ") for defense in depth, even though bash variable
# expansion does not re-interpret expanded contents.
ensure_kv() {
  local key="$1" value="$2" file="$3" sep="${4:- }"
  local escaped_value
  escaped_value=$(printf '%s' "$value" | sed 's/[&\]/\\&/g')
  if grep -Eq "^[#[:space:]]*${key}\b" "$file" 2>/dev/null; then
    sed -i -E "s$(printf '\x01')^[#[:space:]]*(${key})\b.*$(printf '\x01')\1${sep}${escaped_value}$(printf '\x01')" "$file"
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

enable_service() {
  systemctl enable --now "$1"
}

reload_sshd() {
  systemctl reload ssh
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
