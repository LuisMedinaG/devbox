#!/usr/bin/env bash
# Provisions the agent sandbox: a dedicated system user, rootless Podman
# per-agent containers, and an `agent-run` wrapper.
# Agents run with --userns=keep-id, --security-opt=no-new-privileges,
# --cap-drop=ALL, read-only rootfs + tmpfs /tmp, and an isolated network.
# The host never has a `claude` binary on PATH for privileged users.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

AGENT_USER="${AGENT_USER:-agent}"
AGENT_HOME="/home/$AGENT_USER"
WORKSPACES_DIR="/srv/workspaces"
WRAPPER="/usr/local/bin/agent-run"

# --- Dedicated agent system user (no sudo, no docker group) ---
if ! id -u "$AGENT_USER" >/dev/null 2>&1; then
  adduser --system --group --disabled-password --gecos "AI agent runner" \
    --home "$AGENT_HOME" --shell /bin/bash "$AGENT_USER"
fi

# Explicitly ensure no sudoers entry exists for the agent user.
rm -f /etc/sudoers.d/*-"$AGENT_USER" /etc/sudoers.d/"$AGENT_USER"

# subuid/subgid ranges required for rootless Podman.
if ! grep -q "^${AGENT_USER}:" /etc/subuid 2>/dev/null; then
  usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$AGENT_USER"
fi

# Enable linger so the agent user's systemd units survive logout.
loginctl enable-linger "$AGENT_USER"

# Podman config for the agent user: use fuse-overlayfs for rootless storage.
install -d -m 700 -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_HOME/.config/containers"
cat >"$AGENT_HOME/.config/containers/storage.conf" <<'EOF'
[storage]
driver = "overlay"
[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.config/containers/storage.conf"

# --- Workspace root ---
install -d -m 750 -o "$AGENT_USER" -g "$AGENT_USER" "$WORKSPACES_DIR"

# --- Isolated Podman network for agents ---
# Each agent gets --network=agent-net; outbound goes through slirp4netns
# so agents see the internet but cannot reach host services on lo.
# Per-agent egress controls (issue #14) will layer nftables rules on top.
if ! sudo -u "$AGENT_USER" podman network inspect agent-net >/dev/null 2>&1; then
  sudo -u "$AGENT_USER" podman network create \
    --driver bridge \
    --subnet 10.89.0.0/24 \
    --opt "com.docker.network.bridge.name=podman-agent" \
    agent-net
fi

# --- agent-run wrapper ---
# Usage: agent-run <workspace-name> [-- extra podman args]
# Creates an ephemeral container with workspace at /work, no host paths exposed.
cat >"$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="agent"
WORKSPACES_DIR="/srv/workspaces"
IMAGE="${AGENT_IMAGE:-ghcr.io/anthropics/claude-code:latest}"

usage() { echo "Usage: agent-run <workspace-name> [-- extra-podman-args]" >&2; exit 1; }
[[ $# -lt 1 ]] && usage

WORKSPACE="$1"; shift
[[ -z "$WORKSPACE" ]] && usage

WORKSPACE_DIR="$WORKSPACES_DIR/$WORKSPACE"
mkdir -p "$WORKSPACE_DIR"
chown "$AGENT_USER:$AGENT_USER" "$WORKSPACE_DIR"

# Split on -- to pass extra args to podman.
EXTRA_ARGS=()
if [[ "${1:-}" == "--" ]]; then
  shift; EXTRA_ARGS=("$@")
fi

GPU_ARGS=()
if [[ -f /etc/cdi/nvidia.yaml ]]; then
  GPU_ARGS=(--device nvidia.com/gpu=all)
fi

exec sudo -u "$AGENT_USER" podman run --rm \
  --name "agent-${WORKSPACE}-$$" \
  --userns=keep-id \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  --read-only \
  --tmpfs /tmp:rw,size=512m,mode=1777 \
  --tmpfs /run:rw,size=64m \
  --network=agent-net \
  --volume "${WORKSPACE_DIR}:/work:Z,rw" \
  --workdir /work \
  "${GPU_ARGS[@]}" \
  "${EXTRA_ARGS[@]}" \
  "$IMAGE" \
  claude
WRAPPER_EOF
chmod 755 "$WRAPPER"

# --- Negative-access smoke test (CI-friendly) ---
SMOKE_SCRIPT="/usr/local/libexec/agent-sandbox-smoke-test.sh"
install -d /usr/local/libexec
cat >"$SMOKE_SCRIPT" <<'SMOKE_EOF'
#!/usr/bin/env bash
# Asserts that an agent container cannot reach sensitive host resources.
# Exit 0 = sandbox is enforced. Exit 1 = a check passed that should have failed.
set -euo pipefail
PASS=0; FAIL=0

check_blocked() {
  local label="$1"; shift
  if sudo -u agent podman run --rm \
      --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
      --read-only --tmpfs /tmp --network=agent-net \
      alpine:latest sh -c "$*" >/dev/null 2>&1; then
    echo "FAIL: $label — command succeeded but should have been blocked"
    FAIL=$((FAIL+1))
  else
    echo "PASS: $label"
    PASS=$((PASS+1))
  fi
}

check_blocked "read /etc/shadow"        "cat /etc/shadow"
check_blocked "read host ~/.ssh"        "ls /home/luis/.ssh"
check_blocked "sudo -n true"            "sudo -n true"
check_blocked "reach docker socket"     "curl --unix-socket /var/run/docker.sock http://localhost/version"
check_blocked "read tailscale state"    "cat /var/lib/tailscale/tailscaled.state"

echo "---"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
SMOKE_EOF
chmod 755 "$SMOKE_SCRIPT"

log "Agent sandbox provisioned."
log "  Agent user : $AGENT_USER (no sudo, no docker group)"
log "  Workspaces : $WORKSPACES_DIR/<name>"
log "  Wrapper    : $WRAPPER <workspace-name>"
log "  Smoke test : $SMOKE_SCRIPT"
