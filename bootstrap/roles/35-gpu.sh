#!/usr/bin/env bash
# Role 35: NVIDIA GPU enablement (driver + Container Toolkit + CDI spec).
#
# Purpose: lets containers (Podman in role 42, agent sandbox in role 45) access
# an NVIDIA GPU via `--device nvidia.com/gpu=all`. Required only if the host has
# an NVIDIA card and you want CUDA workloads (training, local LLM inference,
# CUDA-accelerated tooling) inside the agent sandbox.
#
# Behavior:
#   - Auto-skips on CPU-only hosts (lspci finds no NVIDIA device).
#   - Installs the driver branch pinned by NVIDIA_DRIVER_BRANCH.
#   - Installs nvidia-container-toolkit and generates a CDI spec at
#     /etc/cdi/nvidia.yaml so containers can reference GPUs by name.
#   - With GPU_PROFILE=datacenter, enables nvidia-persistenced (server cards).
#
# Knobs (override via env or config/versions.conf):
#   GPU_PROFILE          consumer (default) | datacenter | none
#   NVIDIA_DRIVER_BRANCH apt package name of the driver branch
#   CUDA_KEYRING_URL     URL of NVIDIA's cuda-keyring .deb (adds apt repo)
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

if ! lspci 2>/dev/null | grep -qi nvidia; then
  log "No NVIDIA GPU detected — skipping role 35-gpu."
  exit 0
fi

log "NVIDIA GPU detected. Installing drivers and container toolkit."

# Source pinned versions; fall back to defaults defined here.
VERSIONS_ENV="$SCRIPT_DIR/config/versions.conf"
# shellcheck source=/dev/null
[[ -f "$VERSIONS_ENV" ]] && source "$VERSIONS_ENV"

: "${NVIDIA_DRIVER_BRANCH:=nvidia-driver-550-server}"
: "${CUDA_KEYRING_DEB:=cuda-keyring_1.1-1_all.deb}"
: "${CUDA_KEYRING_URL:=https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/${CUDA_KEYRING_DEB}}"
: "${GPU_PROFILE:=consumer}"  # consumer = workstation/laptop GPUs; datacenter = Tesla/A100/H100 (enables nvidia-persistenced)

apt_update_once
apt_install pciutils  # ensures lspci is available on subsequent idempotent runs

# --- CUDA keyring (adds both CUDA and driver repos) ---
if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
  TMP_DEB=$(mktemp --suffix=.deb)
  trap 'rm -f "$TMP_DEB"' EXIT
  curl -fsSL "$CUDA_KEYRING_URL" -o "$TMP_DEB"
  dpkg -i "$TMP_DEB"
  apt-get update -y
  mkdir -p /var/lib/bootstrap && touch /var/lib/bootstrap/apt-updated
fi

# --- NVIDIA driver ---
if ! command -v nvidia-smi >/dev/null 2>&1; then
  apt_install "$NVIDIA_DRIVER_BRANCH"
fi

# --- NVIDIA Container Toolkit ---
if ! command -v nvidia-ctk >/dev/null 2>&1; then
  # The CUDA keyring repo also ships nvidia-container-toolkit.
  apt_install nvidia-container-toolkit
fi

# --- CDI spec (Container Device Interface) ---
# Generates /etc/cdi/nvidia.yaml so rootless Podman can attach the GPU via
# `--device nvidia.com/gpu=all` without privileged mode or ad-hoc bind mounts.
install -d /etc/cdi
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# --- Persistence daemon (keeps GPU initialized between jobs) ---
if [[ "$GPU_PROFILE" == "datacenter" ]]; then
  enable_service nvidia-persistenced
  log "nvidia-persistenced enabled (datacenter profile)."
fi

# --- Smoke test ---
log "Running nvidia-smi smoke test..."
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

log "GPU role complete. CDI spec at /etc/cdi/nvidia.yaml."
log "Agent sandbox smoke test (requires Podman + role 45):"
log "  podman run --rm --device nvidia.com/gpu=all nvcr.io/nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi"
