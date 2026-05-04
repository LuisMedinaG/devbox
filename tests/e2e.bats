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
  # sudo -l exits non-zero when the user has no entries. Asserting on $status
  # alone catches the password-required-sudo case that a NOPASSWD-only grep
  # would silently miss.
  run sudo -l -U "$AGENT_USER"
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q -- "NOPASSWD"
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

@test "agent-run accepts -e KEY=VALUE without rejecting at parse time" {
  # Use a non-existent image so podman fails fast AFTER the wrapper's parser
  # has already accepted the -e args. If parsing rejects -e, agent-run exits
  # with the wrapper's "Error: unknown argument" which we grep for.
  AGENT_IMAGE="does-not-exist:latest" \
    run /usr/local/bin/agent-run "smoke$$" -e "FOO=bar" -e "BAZ=qux"
  [ "$status" -ne 0 ]    # podman pull fails — that's fine
  ! echo "$output" | grep -qi -- "unknown argument"
  ! echo "$output" | grep -qi -- "-e requires KEY=VALUE"
}

# ---------------------------------------------------------------------------
# Sandbox isolation (uses same flags as agent-run; checks rely only on
# binaries shipped in alpine to avoid passing for the wrong reason)
# ---------------------------------------------------------------------------

@test "sandbox: cannot read /etc/shadow" {
  # `cat` is in alpine; this exercises the actual permission check.
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "cat /etc/shadow"
  [ "$status" -ne 0 ]
}

@test "sandbox: docker socket is not exposed inside container" {
  # Use `test -e` (in alpine's busybox) instead of curl so a missing curl
  # binary doesn't cause this test to pass for the wrong reason.
  # If the socket existed inside the container, test -e would exit 0;
  # we want the inverse: socket should not exist.
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "test -e /var/run/docker.sock"
  [ "$status" -ne 0 ]
}

@test "sandbox: NoNewPrivs is set on container processes" {
  # Replaces the old "sudo -n true" check (alpine ships no sudo, so it
  # passed for the wrong reason). This asserts the actual kernel-level
  # flag that prevents setuid-based escalation, regardless of which
  # binaries happen to be in the image.
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c "grep -q 'NoNewPrivs:.*1' /proc/self/status"
  [ "$status" -eq 0 ]
}

@test "sandbox: process runs without any capabilities" {
  # CapEff in /proc/self/status should be all zeros under --cap-drop=ALL.
  run sudo -u "$AGENT_USER" podman run --rm \
    --userns=keep-id --security-opt=no-new-privileges --cap-drop=ALL \
    --read-only --tmpfs /tmp --network=agent-net \
    alpine:latest sh -c 'awk "/^CapEff:/{print \$2}" /proc/self/status | grep -q "^0\+$"'
  [ "$status" -eq 0 ]
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
