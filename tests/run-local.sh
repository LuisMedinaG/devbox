#!/usr/bin/env bash
# Spins up a fresh Ubuntu 24.04 VM via Multipass, runs bootstrap end-to-end,
# then runs the bats E2E test suite. Requires multipass and bats-core on the host.
#
# Usage:
#   tests/run-local.sh                  # full bootstrap + tests
#   tests/run-local.sh --tests-only     # assumes VM already exists
#   tests/run-local.sh --clean          # delete the VM and exit
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="devbox-e2e-$$"
KEEP_VM=0

usage() {
  echo "Usage: $0 [--tests-only] [--keep-vm] [--clean]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-vm)    KEEP_VM=1; shift;;
    --clean)      multipass delete --purge "$VM_NAME" 2>/dev/null || true; exit 0;;
    *) usage;;
  esac
done

cleanup() {
  if [[ $KEEP_VM -eq 0 ]]; then
    echo "==> Cleaning up VM $VM_NAME ..."
    multipass delete --purge "$VM_NAME" 2>/dev/null || true
  else
    echo "==> VM $VM_NAME preserved (--keep-vm). Delete with: multipass delete --purge $VM_NAME"
  fi
}
trap cleanup EXIT INT TERM

# Verify prerequisites.
command -v multipass >/dev/null || { echo "Error: multipass not found. Install from https://multipass.run"; exit 1; }
command -v bats >/dev/null      || { echo "Error: bats not found. Install with: brew install bats-core or apt install bats"; exit 1; }

echo "==> Launching VM $VM_NAME (Ubuntu 24.04, 2 vCPU, 4 GB, 20 GB) ..."
multipass launch 24.04 --name "$VM_NAME" --cpus 2 --memory 4G --disk 20G

echo "==> Copying repo to VM ..."
multipass transfer -r "$REPO_ROOT" "$VM_NAME":/tmp/devbox

echo "==> Installing git on VM ..."
multipass exec "$VM_NAME" -- sudo apt-get install -y git >/dev/null

echo "==> Running bootstrap (GPU_PROFILE=none, SKIP_FIREWALL=0) ..."
multipass exec "$VM_NAME" -- sudo env GPU_PROFILE=none \
  bash /tmp/devbox/bootstrap/bootstrap.sh

echo "==> Installing bats-core on VM ..."
multipass exec "$VM_NAME" -- sudo apt-get install -y bats >/dev/null

echo "==> Running E2E tests ..."
multipass exec "$VM_NAME" -- sudo bats /tmp/devbox/tests/e2e.bats

echo ""
echo "==> All E2E tests passed."
