#!/usr/bin/env bash
# Builds the agent container image that includes Claude Code.
# Claude is NOT installed on the host PATH — agents run via `agent-run`.
# Requires role 45-agent-sandbox (rootless Podman + agent user) to have run first.
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

AGENT_USER="${AGENT_USER:-agent}"
IMAGE_NAME="devbox-claude-code"
IMAGE_TAG="${CLAUDE_CODE_VERSION:-latest}"
CONTAINERFILE="/usr/local/share/devbox/Containerfile.claude-code"

if ! id -u "$AGENT_USER" >/dev/null 2>&1; then
  die "Agent user '$AGENT_USER' not found. Run role 45-agent-sandbox first."
fi

install -d /usr/local/share/devbox

# Containerfile for the Claude Code agent image.
# Uses the official Node LTS base; installs claude-code as a non-root user.
cat >"$CONTAINERFILE" <<'CFILE'
FROM node:22-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user inside the container.
RUN useradd -m -u 1000 -s /bin/bash claudeuser

USER claudeuser
WORKDIR /home/claudeuser

# Install Claude Code globally for this user.
RUN npm install -g @anthropic-ai/claude-code

ENV PATH="/home/claudeuser/.npm-global/bin:/home/claudeuser/node_modules/.bin:${PATH}"

WORKDIR /work
ENTRYPOINT ["claude"]
CFILE

log "Building agent image ${IMAGE_NAME}:${IMAGE_TAG} as $AGENT_USER ..."
sudo -u "$AGENT_USER" podman build \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f "$CONTAINERFILE" \
  /usr/local/share/devbox

# Export the image name so agent-run can pick it up by default.
AGENT_IMAGE_FILE="/etc/devbox/agent-image"
install -d /etc/devbox
echo "${IMAGE_NAME}:${IMAGE_TAG}" >"$AGENT_IMAGE_FILE"

# Patch agent-run to use the locally built image unless overridden.
sed -i "s|IMAGE=\${AGENT_IMAGE:-.*}|IMAGE=\${AGENT_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}|" \
  /usr/local/bin/agent-run

log "Claude Code agent image built. Use: agent-run <workspace-name>"
log "The host has no 'claude' binary — all agent invocations go through the sandbox."
