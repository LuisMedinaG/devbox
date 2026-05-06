#!/usr/bin/env bats
# E2E post-bootstrap assertions.
# Run on the bootstrapped host as root:  bats tests/e2e.bats
# Or via the local runner:               tests/run-local.sh
#
# Requires: bats-core >= 1.10 (apt install bats or https://github.com/bats-core/bats-core)
#
# bootstrap.HARDENING.1 bootstrap.HARDENING.2 bootstrap.HARDENING.3
# bootstrap.HARDENING.4 (fail2ban)
# bootstrap.FIREWALL.1 bootstrap.FIREWALL.2 bootstrap.FIREWALL.3
# bootstrap.USER.1 bootstrap.USER.3 bootstrap.DOCKER.2 bootstrap.DOCKER.3
# bootstrap.SYSTEM.3 bootstrap.SYSTEM.5 bootstrap.SYSTEM.2
# bootstrap.TAILSCALE.1 bootstrap.TAILSCALE.4

setup() {
  USERNAME="${USERNAME:-luis}"
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

# ---------------------------------------------------------------------------
# Podman rootless
# ---------------------------------------------------------------------------

@test "Podman reports rootless for $USERNAME" {
  run sudo -u "$USERNAME" podman info --format '{{.Host.Security.Rootless}}'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---------------------------------------------------------------------------
# System
# ---------------------------------------------------------------------------

@test "swapfile is active" {
  run swapon --show
  echo "$output" | grep -q "swapfile"
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
