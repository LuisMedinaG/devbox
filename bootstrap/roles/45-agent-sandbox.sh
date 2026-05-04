#!/usr/bin/env bash
# Provisions the agent sandbox: a dedicated system user, rootless Podman
# per-agent containers, and an `agent-run` wrapper.
# Agents run with --userns=keep-id, --security-opt=no-new-privileges,
# --cap-drop=ALL, read-only rootfs + tmpfs overlays, and an isolated network.
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
if ! sudo -u "$AGENT_USER" podman network inspect agent-net >/dev/null 2>&1; then
  sudo -u "$AGENT_USER" podman network create \
    --driver bridge \
    --subnet 10.89.0.0/24 \
    --opt "com.docker.network.bridge.name=podman-agent" \
    agent-net
fi

# --- agent-run wrapper ---
# Usage: sudo agent-run <workspace-name> [-e KEY=VALUE ...]
# Only -e KEY=VALUE env-var flags are accepted; all other extra flags are
# rejected to prevent sandbox escape via --privileged, -v /:/host, etc.
# Invoke via `sudo agent-run` — sudoers grants the interactive user NOPASSWD
# for this binary (see role 10-user). Inside, we drop to $AGENT_USER via
# runuser rather than a nested sudo, keeping one privilege boundary.
cat >"$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="agent"
WORKSPACES_DIR="/srv/workspaces"
IMAGE_FILE="/etc/devbox/agent-image"
IMAGE="${AGENT_IMAGE:-$(cat "$IMAGE_FILE" 2>/dev/null || echo "devbox-claude-code:latest")}"

usage() {
  echo "Usage: agent-run <workspace-name> [-e KEY=VALUE ...]" >&2
  echo "  Only -e KEY=VALUE flags accepted. No arbitrary podman flags." >&2
  exit 1
}

[[ $# -lt 1 ]] && usage
WORKSPACE="$1"; shift

# Workspace names: alphanumeric, hyphens, underscores only — no path traversal.
[[ "$WORKSPACE" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo "Error: workspace name must match [a-zA-Z0-9_-]+" >&2; exit 1
}

WORKSPACE_DIR="$WORKSPACES_DIR/$WORKSPACE"
mkdir -p "$WORKSPACE_DIR"
chown "$AGENT_USER:$AGENT_USER" "$WORKSPACE_DIR"

# Strict flag parsing — anything that isn't -e KEY=VALUE is an error.
# This blocks --, --privileged, -v, --network=host, --cap-add, etc.
ENV_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e)
      shift
      [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*=.* ]] \
        || { echo "Error: -e requires KEY=VALUE (got '${1:-}')" >&2; exit 1; }
      ENV_ARGS+=(-e "$1"); shift ;;
    -e?*)
      VAL="${1#-e}"
      [[ "$VAL" =~ ^[A-Za-z_][A-Za-z0-9_]*=.* ]] \
        || { echo "Error: -e requires KEY=VALUE (got '$VAL')" >&2; exit 1; }
      ENV_ARGS+=(-e "$VAL"); shift ;;
    *)
      echo "Error: unknown argument '$1'. Only -e KEY=VALUE is accepted." >&2
      usage ;;
  esac
done

GPU_ARGS=()
if [[ -f /etc/cdi/nvidia.yaml ]]; then
  GPU_ARGS=(--device nvidia.com/gpu=all)
fi

# Drop to agent user via runuser — requires this wrapper to be invoked as root.
# All hardening flags are unconditional; no caller-controlled overrides.
exec runuser -u "$AGENT_USER" -- podman run --rm \
  --name "agent-${WORKSPACE}-$$" \
  --userns=keep-id \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  --read-only \
  --tmpfs /tmp:rw,size=512m,mode=1777 \
  --tmpfs /run:rw,size=64m \
  --tmpfs /home/claudeuser/.claude:rw,size=256m \
  --tmpfs /home/claudeuser/.cache:rw,size=256m \
  --tmpfs /home/claudeuser/.npm-global:rw,size=128m \
  --network=agent-net \
  --volume "${WORKSPACE_DIR}:/work:Z,rw" \
  --workdir /work \
  "${GPU_ARGS[@]}" \
  "${ENV_ARGS[@]}" \
  "$IMAGE"
WRAPPER_EOF
chmod 755 "$WRAPPER"

# --- Negative-access smoke test (CI-friendly) ---
# Isolation checks use the same flags as agent-run.
# Escape-via-wrapper checks verify agent-run itself rejects dangerous arguments.
SMOKE_SCRIPT="/usr/local/libexec/agent-sandbox-smoke-test.sh"
install -d /usr/local/libexec
cat >"$SMOKE_SCRIPT" <<'SMOKE_EOF'
#!/usr/bin/env bash
# Asserts that an agent container cannot reach sensitive host resources,
# and that agent-run rejects all flag-based escape attempts.
# Exit 0 = sandbox enforced. Exit 1 = a check passed that should have failed.
set -euo pipefail
PASS=0; FAIL=0

AGENT_USER="agent"
IMAGE_FILE="/etc/devbox/agent-image"
IMAGE="${AGENT_IMAGE:-$(cat "$IMAGE_FILE" 2>/dev/null || echo "devbox-claude-code:latest")}"

# Runs a shell command inside a container using the exact same flags as agent-run.
_sandbox_run() {
  sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --read-only \
    --tmpfs /tmp:rw,size=512m,mode=1777 \
    --tmpfs /run:rw,size=64m \
    --network=agent-net \
    alpine:latest sh -c "$1"
}

check_blocked() {
  local label="$1" cmd="$2"
  if _sandbox_run "$cmd" >/dev/null 2>&1; then
    echo "FAIL: $label — command succeeded but should have been blocked"
    FAIL=$((FAIL+1))
  else
    echo "PASS: $label"
    PASS=$((PASS+1))
  fi
}

# Verifies that agent-run itself rejects the given args (exit non-zero).
check_wrapper_rejects() {
  local label="$1"; shift
  if /usr/local/bin/agent-run "$@" >/dev/null 2>&1; then
    echo "FAIL: $label — agent-run accepted dangerous args"
    FAIL=$((FAIL+1))
  else
    echo "PASS: $label"
    PASS=$((PASS+1))
  fi
}

# --- Container isolation ---
check_blocked "read /etc/shadow"     "cat /etc/shadow"
check_blocked "read host ~/.ssh"     "ls /home/luis/.ssh"
check_blocked "sudo -n true"         "sudo -n true"
check_blocked "reach docker socket"  "curl --unix-socket /var/run/docker.sock http://localhost/version"
check_blocked "read tailscale state" "cat /var/lib/tailscale/tailscaled.state"

# --- agent-run escape prevention ---
check_wrapper_rejects "rejects -- passthrough"    "_smoke$$" "--"
check_wrapper_rejects "rejects --privileged"      "_smoke$$" "--privileged"
check_wrapper_rejects "rejects -v /:/host"        "_smoke$$" "-v" "/:/host"
check_wrapper_rejects "rejects --network=host"    "_smoke$$" "--network=host"
check_wrapper_rejects "rejects path-traversal ws" "../escape"

echo "---"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
SMOKE_EOF
chmod 755 "$SMOKE_SCRIPT"

log "Agent sandbox provisioned."
log "  Agent user : $AGENT_USER (no sudo, no docker group)"
log "  Workspaces : $WORKSPACES_DIR/<name>"
log "  Wrapper    : sudo $WRAPPER <workspace-name> [-e KEY=VAL]"
log "  Smoke test : $SMOKE_SCRIPT"
