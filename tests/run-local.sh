#!/usr/bin/env bash
# Spins up a fresh Ubuntu 24.04 VM via Multipass, runs bootstrap end-to-end,
# then runs the bats E2E test suite. Requires multipass and bats-core on the host.
#
# Usage:
#   tests/run-local.sh                  # full bootstrap + tests
#   tests/run-local.sh --tests-only     # skip bootstrap; re-run bats only
#   tests/run-local.sh --keep-vm        # leave VM running for inspection
#   tests/run-local.sh --clean          # delete the VM and exit
#
# Override the VM name with $DEVBOX_E2E_VM (default: devbox-e2e). The default
# is stable across runs so --tests-only and --clean target the same VM.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="${DEVBOX_E2E_VM:-devbox-e2e}"
KEEP_VM=0
TESTS_ONLY=0
CLEAN_ONLY=0

usage() {
  echo "Usage: $0 [--tests-only] [--keep-vm] [--clean]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-vm)    KEEP_VM=1; shift;;
    --tests-only) TESTS_ONLY=1; KEEP_VM=1; shift;;
    --clean)      CLEAN_ONLY=1; shift;;
    *) usage;;
  esac
done

# Verify prerequisites up front so a missing tool doesn't fail mid-bootstrap.
command -v multipass >/dev/null || { echo "Error: multipass not found. Install from https://multipass.run"; exit 1; }

if [[ $CLEAN_ONLY -eq 1 ]]; then
  echo "==> Deleting VM $VM_NAME ..."
  multipass delete --purge "$VM_NAME" 2>/dev/null || true
  exit 0
fi

cleanup() {
  if [[ $KEEP_VM -eq 0 ]]; then
    echo "==> Cleaning up VM $VM_NAME ..."
    multipass delete --purge "$VM_NAME" 2>/dev/null || true
  else
    echo "==> VM $VM_NAME preserved. Delete with: $0 --clean"
  fi
}
trap cleanup EXIT INT TERM

if [[ $TESTS_ONLY -eq 0 ]]; then
  # Refuse to clobber an existing VM with the same name unintentionally.
  if multipass info "$VM_NAME" >/dev/null 2>&1; then
    echo "Error: VM $VM_NAME already exists. Run '$0 --clean' first or set DEVBOX_E2E_VM=<name>." >&2
    exit 1
  fi

  echo "==> Launching VM $VM_NAME (Ubuntu 24.04, 2 vCPU, 4 GB, 20 GB) ..."
  multipass launch 24.04 --name "$VM_NAME" --cpus 2 --memory 4G --disk 20G

  echo "==> Copying repo to VM ..."
  multipass transfer -r "$REPO_ROOT" "$VM_NAME":/tmp/devbox

  echo "==> Installing git on VM ..."
  multipass exec "$VM_NAME" -- sudo apt-get update -y >/dev/null
  multipass exec "$VM_NAME" -- sudo apt-get install -y git >/dev/null

  echo "==> Running bootstrap (GPU_PROFILE=none, SKIP_FIREWALL=0) ..."
  multipass exec "$VM_NAME" -- sudo env GPU_PROFILE=none \
    bash /tmp/devbox/bootstrap/bootstrap.sh

  echo "==> Installing bats-core on VM ..."
  multipass exec "$VM_NAME" -- sudo apt-get install -y bats >/dev/null
else
  multipass info "$VM_NAME" >/dev/null \
    || { echo "Error: VM $VM_NAME does not exist; remove --tests-only to provision it." >&2; exit 1; }
  # Refresh the test files in case they changed since the last run.
  multipass transfer -r "$REPO_ROOT/tests" "$VM_NAME":/tmp/devbox/
fi

echo "==> Running E2E tests ..."
multipass exec "$VM_NAME" -- sudo bats /tmp/devbox/tests/e2e.bats

echo ""
echo "==> All E2E tests passed."
