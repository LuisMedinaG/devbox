#!/usr/bin/env bash
# Update pinned tool versions in config/versions.conf.
# bootstrap.VERSIONS.1 bootstrap.VERSIONS.2 bootstrap.VERSIONS.3
# bootstrap.VERSIONS.4 bootstrap.VERSIONS.5 bootstrap.VERSIONS.6
#
# Usage:
#   update-versions.sh                # check all tools
#   update-versions.sh --update       # rewrite versions.conf with new pins
#   update-versions.sh [--update] go  # restrict to a single tool
#
# Set GITHUB_TOKEN to avoid GitHub API rate limits (60 req/hr unauthenticated).
# bootstrap.VERSIONS.6
#
# Adding a new tool:
#   1. Add its pins to config/versions.conf (NAME_VERSION, NAME_SHA256_*).
#   2. Define <name>::latest (echo upstream version) and <name>::sync <ver>
#      (write new sha256s via set_pin).
#   3. Append `register_tool <name> <NAME_VERSION>` in the registry section.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_CONF="$SCRIPT_DIR/config/versions.conf"

# ---------- output ----------

GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { printf "  ${GRN}✓${NC} %-10s %s\n"      "$1" "$2"; }
upd()  { printf "  ${YLW}↑${NC} %-10s %s → %s\n" "$1" "$2" "$3"; }
warn() { printf "  ${RED}!${NC} %-10s %s\n"      "$1" "$2" >&2; }

# ---------- portable helpers ----------

sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum
  else shasum -a 256
  fi
}

sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"
  else sed -i '' "$@"
  fi
}

# ---------- fetch primitives (the "factory" parts a tool plugin composes) ----------

# sha256 of a remote artifact (we download to hash, not to install).
remote_sha256()   { curl -fsSL "$1" | sha256_cmd | awk '{print $1}'; }

# sha256 from a sidecar file shaped like "<hex>  filename".
sidecar_sha256()  { curl -fsSL "$1" | awk '{print $1}'; }

# sha256 for a filename pattern within a SHASUMS-style manifest.
manifest_sha256() { curl -fsSL "$1" | awk -v p="$2" '$0 ~ p {print $1; exit}'; }

# Latest GitHub release tag with optional prefix stripped (e.g. "bun-").
# Always strips a leading "v" so the result is bare semver.
# bootstrap.VERSIONS.4
gh_latest() {
  local repo="$1" prefix="${2:-}"
  curl -fsSL \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"tag_name"' | head -1 \
    | sed -E "s/.*\"tag_name\": *\"${prefix}v?//; s/\".*//"
}

# Reject anything that isn't x.y.z (with optional -suffix).
# bootstrap.VERSIONS.5
require_semver() {
  [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] \
    || { warn "$1" "unparseable version: '$2'"; return 1; }
}

# ---------- versions.conf I/O ----------

set_pin() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || { warn "$key" "empty value, refusing to write"; return 1; }
  sed_inplace "s|^${key}=.*|${key}=\"${value}\"|" "$VERSIONS_CONF"
}

# ---------- tool registry ----------

REGISTERED_TOOLS=()
declare -A VAR_OF=()

register_tool() {
  REGISTERED_TOOLS+=("$1")
  VAR_OF[$1]="$2"
}

# ---------- tool plugins ----------

go::latest() {
  curl -fsSL "https://go.dev/dl/?mode=json" \
    | grep '"version"' | head -1 | sed 's/.*"go//;s/".*//'
}
go::sync() {
  local v="$1"
  set_pin GO_VERSION      "$v"
  set_pin GO_SHA256_AMD64 "$(remote_sha256 "https://go.dev/dl/go${v}.linux-amd64.tar.gz")"
  set_pin GO_SHA256_ARM64 "$(remote_sha256 "https://go.dev/dl/go${v}.linux-arm64.tar.gz")"
}
register_tool go GO_VERSION

fnm::latest() { gh_latest Schniz/fnm; }
fnm::sync() {
  local v="$1"
  set_pin FNM_VERSION "$v"
  set_pin FNM_SHA256  "$(remote_sha256 "https://github.com/Schniz/fnm/releases/download/v${v}/fnm-linux.zip")"
}
register_tool fnm FNM_VERSION

uv::latest() { gh_latest astral-sh/uv; }
uv::sync() {
  local v="$1"
  local base="https://github.com/astral-sh/uv/releases/download/${v}"
  set_pin UV_VERSION      "$v"
  set_pin UV_SHA256_AMD64 "$(remote_sha256 "${base}/uv-x86_64-unknown-linux-musl.tar.gz")"
  set_pin UV_SHA256_ARM64 "$(remote_sha256 "${base}/uv-aarch64-unknown-linux-musl.tar.gz")"
}
register_tool uv UV_VERSION

# Bun tags releases as "bun-vX.Y.Z" — strip the "bun-" prefix.
bun::latest() { gh_latest oven-sh/bun "bun-"; }
bun::sync() {
  local v="$1"
  local manifest="https://github.com/oven-sh/bun/releases/download/bun-v${v}/SHASUMS256.txt"
  set_pin BUN_VERSION      "$v"
  set_pin BUN_SHA256_AMD64 "$(manifest_sha256 "$manifest" 'bun-linux-x64-baseline\.zip$')"
  set_pin BUN_SHA256_ARM64 "$(manifest_sha256 "$manifest" 'bun-linux-aarch64\.zip$')"
}
register_tool bun BUN_VERSION

# Rustup ships via static.rust-lang.org, not GitHub Releases.
rustup::latest() {
  curl -fsSL "https://static.rust-lang.org/rustup/release-stable.toml" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
rustup::sync() {
  local v="$1"
  local base="https://static.rust-lang.org/rustup/archive/${v}"
  set_pin RUSTUP_VERSION      "$v"
  set_pin RUSTUP_SHA256_AMD64 "$(sidecar_sha256 "${base}/x86_64-unknown-linux-gnu/rustup-init.sha256")"
  set_pin RUSTUP_SHA256_ARM64 "$(sidecar_sha256 "${base}/aarch64-unknown-linux-gnu/rustup-init.sha256")"
}
register_tool rustup RUSTUP_VERSION

# ---------- driver ----------

UPDATE=0
SELECTED=""
for arg in "$@"; do
  case "$arg" in
    --update)  UPDATE=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        warn args "unknown flag: $arg"; exit 2 ;;
    *)         SELECTED="$arg" ;;
  esac
done

[[ -f "$VERSIONS_CONF" ]] || { warn config "not found: $VERSIONS_CONF"; exit 1; }
# shellcheck disable=SC1090
source "$VERSIONS_CONF"

if [[ -n "$SELECTED" && -z "${VAR_OF[$SELECTED]:-}" ]]; then
  warn args "unknown tool: $SELECTED (known: ${REGISTERED_TOOLS[*]})"
  exit 2
fi

echo "Checking versions..."
outdated=0

for tool in "${REGISTERED_TOOLS[@]}"; do
  [[ -z "$SELECTED" || "$SELECTED" == "$tool" ]] || continue

  var="${VAR_OF[$tool]}"
  current="${!var-}"
  current="${current#v}"   # tolerate accidental v-prefix in versions.conf

  if ! latest=$("${tool}::latest") || ! require_semver "$tool" "$latest"; then
    warn "$tool" "skipped — could not determine latest"
    continue
  fi

  if [[ "$current" == "$latest" ]]; then
    ok "$tool" "$current"
    continue
  fi

  upd "$tool" "$current" "$latest"
  outdated=$((outdated + 1))

  if [[ "$UPDATE" == 1 ]]; then
    echo "    syncing ${tool}@${latest}..."
    "${tool}::sync" "$latest"
  fi
done

echo
if [[ "$outdated" -eq 0 ]]; then
  printf '%bAll tools up to date.%b\n' "$GRN" "$NC"
elif [[ "$UPDATE" == 1 ]]; then
  printf '%bversions.conf updated. Review with: git diff config/versions.conf%b\n' "$GRN" "$NC"
else
  printf '%b%d tool(s) outdated. Run with --update to apply.%b\n' "$YLW" "$outdated" "$NC"
fi
