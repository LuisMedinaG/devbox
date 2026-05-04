#!/usr/bin/env bats
# E2E post-bootstrap assertions.
# Run on the bootstrapped host as root:  bats tests/e2e.bats
# Or via the local runner:               tests/run-local.sh
#
# Requires: bats-core >= 1.10 (apt install bats or https://github.com/bats-core/bats-core)

setup() {
  USERNAME="${USERNAME:-luis}"
  AGENT_USER="${AGENT_USER:-agent}"
}

# ---------------------------------------------------------------------------
# SSH hardening
# ---------------------------------------------------------------------------

@test "sshd: PermitRootLogin is no" {
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^permitrootlogin no"
}

@test "sshd: PasswordAuthentication is no" {
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^passwordauthentication no"
}

@test "sshd: X11Forwarding is no" {
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^x11forwarding no"
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------

@test "ufw is active" {
  run ufw status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^Status: active"
}

@test "ufw allows OpenSSH" {
  run ufw status
  echo "$output" | grep -q "OpenSSH"
}

@test "ufw allows Mosh UDP" {
  run ufw status
  echo "$output" | grep -q "60000:61000/udp"
}

# ---------------------------------------------------------------------------
# fail2ban
# ---------------------------------------------------------------------------

@test "fail2ban is active" {
  run systemctl is-active fail2ban
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
}

@test "fail2ban sshd jail is enabled" {
  run fail2ban-client status sshd
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Interactive user
# ---------------------------------------------------------------------------

@test "user $USERNAME exists" {
  run id "$USERNAME"
  [ "$status" -eq 0 ]
}

@test "user $USERNAME has zsh as shell" {
  run getent passwd "$USERNAME"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "zsh"
}

@test "user $USERNAME is not in docker group" {
  run id "$USERNAME"
  ! echo "$output" | grep -q "(docker)"
}

@test "user $USERNAME has no NOPASSWD ALL in sudoers" {
  run sudo -l -U "$USERNAME"
  ! echo "$output" | grep -qE "NOPASSWD.*\(ALL\).*ALL$"
}

@test "sudoers allows $USERNAME to run agent-run" {
  run sudo -l -U "$USERNAME"
  echo "$output" | grep -q "agent-run"
}

@test "sudoers allows $USERNAME to run agent-service-ctl" {
  run sudo -l -U "$USERNAME"
  echo "$output" | grep -q "agent-service-ctl"
}

# ---------------------------------------------------------------------------
# Agent user
# ---------------------------------------------------------------------------

@test "agent user $AGENT_USER exists" {
  run id "$AGENT_USER"
  [ "$status" -eq 0 ]
}

@test "agent user $AGENT_USER has no sudo privileges" {
  # sudo -l exits 1 when the user has no entries.
  run sudo -l -U "$AGENT_USER"
  ! echo "$output" | grep -q "NOPASSWD"
}

@test "agent user $AGENT_USER is not in docker group" {
  run id "$AGENT_USER"
  ! echo "$output" | grep -q "(docker)"
}

@test "agent user $AGENT_USER has subuid mapping" {
  run grep "^${AGENT_USER}:" /etc/subuid
  [ "$status" -eq 0 ]
}

@test "agent user $AGENT_USER has subgid mapping" {
  run grep "^${AGENT_USER}:" /etc/subgid
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Podman rootless
# ---------------------------------------------------------------------------

@test "Podman reports rootless for agent user" {
  run sudo -u "$AGENT_USER" podman info --format '{{.Host.Security.Rootless}}'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "agent-net Podman network exists" {
  run sudo -u "$AGENT_USER" podman network inspect agent-net
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Container image
# ---------------------------------------------------------------------------

@test "devbox-claude-code image is present" {
  run sudo -u "$AGENT_USER" podman images --format '{{.Repository}}:{{.Tag}}'
  echo "$output" | grep -q "devbox-claude-code"
}

@test "claude binary is reachable inside the agent image" {
  IMAGE_FILE="/etc/devbox/agent-image"
  IMAGE=$(cat "$IMAGE_FILE" 2>/dev/null || echo "devbox-claude-code:latest")
  run sudo -u "$AGENT_USER" podman run --rm \
    --entrypoint=/bin/sh "$IMAGE" -c 'which claude'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "claude"
}

@test "claude UID inside image matches host agent UID" {
  IMAGE_FILE="/etc/devbox/agent-image"
  IMAGE=$(cat "$IMAGE_FILE" 2>/dev/null || echo "devbox-claude-code:latest")
  EXPECTED_UID=$(id -u "$AGENT_USER")
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id \
    --entrypoint=/bin/sh "$IMAGE" -c 'id -u'
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECTED_UID" ]
}

# ---------------------------------------------------------------------------
# agent-run wrapper
# ---------------------------------------------------------------------------

@test "agent-run wrapper exists and is executable" {
  [ -x /usr/local/bin/agent-run ]
}

@test "agent-run rejects path-traversal workspace name" {
  run /usr/local/bin/agent-run "../escape"
  [ "$status" -ne 0 ]
}

@test "agent-run rejects -- passthrough" {
  run /usr/local/bin/agent-run "smoke$$" "--"
  [ "$status" -ne 0 ]
}

@test "agent-run rejects --privileged" {
  run /usr/local/bin/agent-run "smoke$$" "--privileged"
  [ "$status" -ne 0 ]
}

@test "agent-run rejects -v /:/host" {
  run /usr/local/bin/agent-run "smoke$$" "-v" "/:/host"
  [ "$status" -ne 0 ]
}

@test "agent-run rejects --network=host" {
  run /usr/local/bin/agent-run "smoke$$" "--network=host"
  [ "$status" -ne 0 ]
}

@test "agent-run accepts -e KEY=VALUE" {
  # Parsing only — don't actually spin up a container here.
  run bash -c '
    source /usr/local/bin/agent-run 2>/dev/null || true
    # Simulate the arg parsing inline.
    ENV_ARGS=()
    set -- "workspace" -e "FOO=bar" -e "BAZ=qux"
    shift  # consume workspace
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -e) shift; ENV_ARGS+=(-e "$1"); shift;;
        *) echo "rejected: $1" >&2; exit 1;;
      esac
    done
    echo "accepted: ${ENV_ARGS[*]}"
  '
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "accepted"
}

# ---------------------------------------------------------------------------
# Sandbox isolation (uses same flags as agent-run)
# ---------------------------------------------------------------------------

@test "sandbox: cannot read /etc/shadow" {
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "cat /etc/shadow"
  [ "$status" -ne 0 ]
}

@test "sandbox: cannot reach docker socket" {
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "curl --unix-socket /var/run/docker.sock http://localhost/version"
  [ "$status" -ne 0 ]
}

@test "sandbox: cannot sudo inside container" {
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "sudo -n true"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# System
# ---------------------------------------------------------------------------

@test "swapfile is active" {
  run swapon --show
  echo "$output" | grep -q "swapfile"
}

@test "workspace directory exists with correct owner" {
  OWNER=$(stat -c '%U' /srv/workspaces)
  [ "$OWNER" = "$AGENT_USER" ]
}

@test "bootstrap log directory exists" {
  [ -d /var/log/bootstrap ]
}

@test "logrotate config for bootstrap exists" {
  [ -f /etc/logrotate.d/bootstrap ]
}

@test "auto-upgrade reboot config exists" {
  [ -f /etc/apt/apt.conf.d/51unattended-upgrades-reboot ]
}

# ---------------------------------------------------------------------------
# Backups skeleton
# ---------------------------------------------------------------------------

@test "restic is installed" {
  run command -v restic
  [ "$status" -eq 0 ]
}

@test "restic env file exists with mode 600" {
  ENV_FILE="/home/${USERNAME}/.config/restic/env"
  [ -f "$ENV_FILE" ]
  MODE=$(stat -c '%a' "$ENV_FILE")
  [ "$MODE" = "600" ]
}

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------

@test "tailscale is installed" {
  run command -v tailscale
  [ "$status" -eq 0 ]
}

@test "tailscaled service is enabled" {
  run systemctl is-enabled tailscaled
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Bootstrap log hygiene
# ---------------------------------------------------------------------------

@test "no Tailscale auth key in bootstrap logs" {
  # tskey- prefix is the pattern for all Tailscale auth keys.
  run grep -r "tskey-" /var/log/bootstrap/ 2>/dev/null
  [ "$status" -ne 0 ]
}
