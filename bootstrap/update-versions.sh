#!/usr/bin/env bash
# Checks for newer versions of all tools pinned in config/versions.conf.
# Downloads are not executed — only sha256s of release artifacts are fetched.
#
# Usage:
#   ./update-versions.sh           # dry-run: show what's outdated
#   ./update-versions.sh --update  # fetch new sha256s and rewrite versions.conf
#
# Set GITHUB_TOKEN to avoid GitHub API rate-limiting (60 req/hr unauthenticated).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_CONF="$SCRIPT_DIR/config/versions.conf"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

GRN='\033[0;32m' YLW='\033[1;33m' NC='\033[0m'
outdated=0

# --- Helpers ---

# sha256 of a remote URL; works on macOS (shasum) and Linux (sha256sum).
remote_sha256() {
  curl -fsSL "$1" \
    | (command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256) \
    | awk '{print $1}'
}

# sed -i that works on both BSD (macOS) and GNU.
sed_inplace() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

set_var() {
  sed_inplace "s|^${1}=.*|${1}=\"${2}\"|" "$VERSIONS_CONF"
}

# Fetch latest GitHub release tag (strips leading 'v').
gh_latest() {
  curl -fsSL \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/${1}/releases/latest" \
    | grep '"tag_name"' | head -1 \
    | sed 's/.*"tag_name": *"v\{0,1\}//;s/".*//'
}

# Print status and return 0 if an update is available, 1 if already current.
check() {
  local name="$1" current="$2" latest="$3"
  if [[ "$current" == "$latest" ]]; then
    printf "  ${GRN}✓${NC} %-10s %s\n" "$name" "$current"
    return 1
  fi
  printf "  ${YLW}↑${NC} %-10s %s → %s\n" "$name" "$current" "$latest"
  outdated=$((outdated + 1))
}

# --- Load current pins ---
source "$VERSIONS_CONF"

echo "Checking versions..."
echo

# --- Go ---
# https://go.dev/dl/?mode=json returns the latest stable release.
GO_LATEST=$(curl -fsSL "https://go.dev/dl/?mode=json" \
  | grep '"version"' | head -1 | sed 's/.*"go//;s/".*//')
if check "go" "$GO_VERSION" "$GO_LATEST" && [[ "$UPDATE" == "1" ]]; then
  echo "    Fetching Go sha256s..."
  set_var GO_VERSION        "$GO_LATEST"
  set_var GO_SHA256_AMD64   "$(remote_sha256 "https://go.dev/dl/go${GO_LATEST}.linux-amd64.tar.gz")"
  set_var GO_SHA256_ARM64   "$(remote_sha256 "https://go.dev/dl/go${GO_LATEST}.linux-arm64.tar.gz")"
fi

# --- fnm ---
# Single binary for all arches; one sha256 covers both.
# versions.conf stores the bare version (no v-prefix); 60-langs.sh adds v in the URL.
FNM_LATEST=$(gh_latest "Schniz/fnm")
if check "fnm" "$FNM_VERSION" "$FNM_LATEST" && [[ "$UPDATE" == "1" ]]; then
  echo "    Fetching fnm sha256..."
  set_var FNM_VERSION "$FNM_LATEST"
  set_var FNM_SHA256  "$(remote_sha256 "https://github.com/Schniz/fnm/releases/download/v${FNM_LATEST}/fnm-linux.zip")"
fi

# --- uv ---
UV_LATEST=$(gh_latest "astral-sh/uv")
if check "uv" "$UV_VERSION" "$UV_LATEST" && [[ "$UPDATE" == "1" ]]; then
  echo "    Fetching uv sha256s..."
  set_var UV_VERSION        "$UV_LATEST"
  set_var UV_SHA256_AMD64   "$(remote_sha256 "https://github.com/astral-sh/uv/releases/download/${UV_LATEST}/uv-x86_64-unknown-linux-musl.tar.gz")"
  set_var UV_SHA256_ARM64   "$(remote_sha256 "https://github.com/astral-sh/uv/releases/download/${UV_LATEST}/uv-aarch64-unknown-linux-musl.tar.gz")"
fi

# --- Bun ---
# Hashes come from the official SHASUMS256.txt in the release assets.
# Must match the artifact names used in 60-langs.sh:
#   amd64 → bun-linux-x64-baseline.zip
#   arm64 → bun-linux-aarch64.zip
# Bun tags as "bun-v1.x.y" (not "v1.x.y"), so strip the "bun-v" prefix.
BUN_LATEST=$(gh_latest "oven-sh/bun" | sed 's/^bun-v//')
if check "bun" "$BUN_VERSION" "$BUN_LATEST" && [[ "$UPDATE" == "1" ]]; then
  echo "    Fetching Bun sha256s from SHASUMS256.txt..."
  SHASUMS=$(curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_LATEST}/SHASUMS256.txt")
  set_var BUN_VERSION        "$BUN_LATEST"
  set_var BUN_SHA256_AMD64   "$(awk '/bun-linux-x64-baseline\.zip$/ {print $1}' <<<"$SHASUMS")"
  set_var BUN_SHA256_ARM64   "$(awk '/bun-linux-aarch64\.zip$/ {print $1}' <<<"$SHASUMS")"
fi

# --- Rust (rustup-init) ---
# Rust publishes a sha256 sidecar file alongside each rustup-init binary.
RUSTUP_LATEST=$(curl -fsSL "https://static.rust-lang.org/rustup/release-stable.toml" \
  | awk -F'"' '/^version/ {print $2}')
if check "rustup" "$RUSTUP_VERSION" "$RUSTUP_LATEST" && [[ "$UPDATE" == "1" ]]; then
  echo "    Fetching rustup sha256s from sidecar files..."
  set_var RUSTUP_VERSION        "$RUSTUP_LATEST"
  set_var RUSTUP_SHA256_AMD64   "$(curl -fsSL "https://static.rust-lang.org/rustup/archive/${RUSTUP_LATEST}/x86_64-unknown-linux-gnu/rustup-init.sha256" | awk '{print $1}')"
  set_var RUSTUP_SHA256_ARM64   "$(curl -fsSL "https://static.rust-lang.org/rustup/archive/${RUSTUP_LATEST}/aarch64-unknown-linux-gnu/rustup-init.sha256" | awk '{print $1}')"
fi

echo
if [[ "$outdated" -eq 0 ]]; then
  printf "${GRN}All tools up to date.${NC}\n"
elif [[ "$UPDATE" == "1" ]]; then
  printf "${GRN}versions.conf updated. Review with: git diff config/versions.conf${NC}\n"
else
  printf "${YLW}${outdated} tool(s) outdated. Run with --update to apply.${NC}\n"
fi
