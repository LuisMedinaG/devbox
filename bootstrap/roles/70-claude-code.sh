#!/usr/bin/env bash
# Builds the agent container image that includes Claude Code.
# Claude is NOT installed on the host PATH — agents run via `sudo agent-run`.
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

# Resolve the agent user's UID/GID so the in-container user matches the host
# agent UID exactly. Combined with --userns=keep-id in agent-run, the container
# process runs as the same numeric UID as the host agent user, ensuring
# workspace volume writes land with the correct ownership.
AGENT_UID=$(id -u "$AGENT_USER")
AGENT_GID=$(id -g "$AGENT_USER")

install -d /usr/local/share/devbox

# Containerfile for the Claude Code agent image.
# claudeuser is created with the same UID/GID as the host agent user (via
# build args) so --userns=keep-id in agent-run keeps the UID consistent.
# npm prefix is set before the global install so it writes to the user's home
# rather than /usr/local (which claudeuser cannot write to).
cat >"$CONTAINERFILE" <<'CFILE'
FROM node:22-slim

ARG AGENT_UID=1000
ARG AGENT_GID=1000

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create in-container user whose UID/GID matches the host agent user.
RUN groupadd -g ${AGENT_GID} claudeuser && \
    useradd -m -u ${AGENT_UID} -g claudeuser -s /bin/bash claudeuser && \
    mkdir -p /home/claudeuser/.npm-global && \
    chown -R claudeuser:claudeuser /home/claudeuser

USER claudeuser
WORKDIR /home/claudeuser

# Set npm prefix before installing — without this, `npm install -g` writes to
# /usr/local which is not writable by claudeuser and the install silently fails.
RUN npm config set prefix /home/claudeuser/.npm-global && \
    npm install -g @anthropic-ai/claude-code

ENV PATH="/home/claudeuser/.npm-global/bin:${PATH}"

WORKDIR /work
ENTRYPOINT ["claude"]
CFILE

log "Building agent image ${IMAGE_NAME}:${IMAGE_TAG} as $AGENT_USER (UID=${AGENT_UID}) ..."
sudo -u "$AGENT_USER" podman build \
  --build-arg AGENT_UID="$AGENT_UID" \
  --build-arg AGENT_GID="$AGENT_GID" \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f "$CONTAINERFILE" \
  /usr/local/share/devbox

# Verify the installed binary is reachable inside the image.
log "Verifying claude binary inside image ..."
sudo -u "$AGENT_USER" podman run --rm \
  --entrypoint=/bin/sh \
  "${IMAGE_NAME}:${IMAGE_TAG}" \
  -c 'which claude && claude --version' \
  || die "claude binary not found in image — check npm prefix and PATH."

# Persist the image name so agent-run picks it up by default.
install -d /etc/devbox
echo "${IMAGE_NAME}:${IMAGE_TAG}" >/etc/devbox/agent-image

log "Claude Code agent image built. Use: sudo agent-run <workspace-name>"
log "The host has no 'claude' binary — all agent invocations go through the sandbox."
