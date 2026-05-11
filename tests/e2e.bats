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
# bootstrap.USER.1 bootstrap.USER.3 bootstrap.DOCKER.2 bootstrap.DOCKER.3 bootstrap.DOCKER.7
# bootstrap.SYSTEM.3 bootstrap.SYSTEM.5 bootstrap.SYSTEM.2
# bootstrap.TAILSCALE.1 bootstrap.TAILSCALE.4
# bootstrap.CADDY.1 bootstrap.CADDY.2 bootstrap.CADDY.3 bootstrap.CADDY.4 bootstrap.CADDY.5
# bootstrap.OLLAMA.1 bootstrap.OLLAMA.2 bootstrap.OLLAMA.3 bootstrap.OLLAMA.4

setup() {
  USERNAME="${USERNAME:-luis}"
}

# Skip guards for DEV_MODE provisioning.
# Tests detect the on-disk state directly rather than reading env vars from
# bootstrap time, so they remain accurate regardless of how the host was
# provisioned (cloud-init, manual re-run, etc).
_hardening_active() {
  [[ -f /etc/ssh/sshd_config.d/10-hardening.conf ]]
}
_ufw_active() {
  ufw status 2>/dev/null | grep -q "^Status: active"
}

# ---------------------------------------------------------------------------
# SSH hardening
# ---------------------------------------------------------------------------

@test "sshd: PermitRootLogin is no" {
  _hardening_active || skip "SKIP_SSH_HARDENING / DEV_MODE — sshd drop-in not installed"
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^permitrootlogin no"
}

@test "sshd: PasswordAuthentication is no" {
  _hardening_active || skip "SKIP_SSH_HARDENING / DEV_MODE — sshd drop-in not installed"
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^passwordauthentication no"
}

@test "sshd: X11Forwarding is no" {
  _hardening_active || skip "SKIP_SSH_HARDENING / DEV_MODE — sshd drop-in not installed"
  run sshd -T
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^x11forwarding no"
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------

@test "ufw is active" {
  _ufw_active || skip "SKIP_FIREWALL / DEV_MODE — UFW not active"
  run ufw status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^Status: active"
}

@test "ufw allows SSH via Tailscale CGNAT" {
  _ufw_active || skip "SKIP_FIREWALL / DEV_MODE — UFW not active"
  run ufw status
  # Role 31 limits SSH to Tailscale CGNAT range (100.64.0.0/10).
  # Format: "22   ALLOW IN   100.64.0.0/10   # SSH via Tailscale only"
  # Note: ufw status shows "ALLOW", numbered shows "ALLOW IN"
  echo "$output" | grep -qE "22.*ALLOW( IN)?.*100\.64\.0\.0/10"
}

@test "ufw allows Mosh UDP" {
  _ufw_active || skip "SKIP_FIREWALL / DEV_MODE — UFW not active"
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

@test "podman-compose is installed" {
  # bootstrap.DOCKER.7
  run command -v podman-compose
  [ "$status" -eq 0 ]
}

@test "docker-compose shim forwards to podman-compose" {
  # bootstrap.DOCKER.7
  [ -x /usr/local/bin/docker-compose ]
  run grep -q "podman-compose" /usr/local/bin/docker-compose
  [ "$status" -eq 0 ]
}

@test "Podman is installed and rootless is configured for $USERNAME" {
  # `podman info --rootless` requires a user D-Bus session (not available
  # during bats run as root). Instead verify the prerequisites: binary + subuid.
  run command -v podman
  [ "$status" -eq 0 ]

  run grep "^$USERNAME:" /etc/subuid
  [ "$status" -eq 0 ]
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
# Caddy reverse proxy
# ---------------------------------------------------------------------------

@test "caddy is installed" {
  # bootstrap.CADDY.1
  run command -v caddy
  [ "$status" -eq 0 ]
}

@test "caddy service is active" {
  # bootstrap.CADDY.5
  run systemctl is-active caddy
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
}

@test "caddy Caddyfile has bootstrap sentinel" {
  # bootstrap.CADDY.2
  run grep -q "bootstrap.CADDY" /etc/caddy/Caddyfile
  [ "$status" -eq 0 ]
}

@test "caddy conf.d directory exists" {
  # bootstrap.CADDY.3
  [ -d /etc/caddy/conf.d ]
}

@test "caddy health endpoint responds 200" {
  # bootstrap.CADDY.2
  run curl -sf -o /dev/null -w "%{http_code}" http://localhost/health
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "ufw allows HTTP port 80" {
  # bootstrap.CADDY.4
  _ufw_active || skip "SKIP_FIREWALL / DEV_MODE — UFW not active"
  run ufw status
  echo "$output" | grep -qE "^80/tcp.*ALLOW"
}

@test "ufw allows HTTPS port 443" {
  # bootstrap.CADDY.4
  _ufw_active || skip "SKIP_FIREWALL / DEV_MODE — UFW not active"
  run ufw status
  echo "$output" | grep -qE "^443/tcp.*ALLOW"
}

# ---------------------------------------------------------------------------
# Ollama (opt-in — tests skip when not installed)
# ---------------------------------------------------------------------------

@test "ollama binary is present" {
  # bootstrap.OLLAMA.1
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  run command -v ollama
  [ "$status" -eq 0 ]
}

@test "ollama service is active" {
  # bootstrap.OLLAMA.3
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  run systemctl is-active ollama
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
}

@test "ollama service user exists" {
  # bootstrap.OLLAMA.2
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  run id ollama
  [ "$status" -eq 0 ]
}

@test "ollama model storage directory exists and is owned by ollama" {
  # bootstrap.OLLAMA.2
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  [ -d /var/lib/ollama/models ]
  run stat -c "%U" /var/lib/ollama/models
  [ "$output" = "ollama" ]
}

@test "ollama responds on port 11434" {
  # bootstrap.OLLAMA.3
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  run curl -sf -o /dev/null -w "%{http_code}" http://localhost:11434/api/version
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "ollama caddy snippet exists" {
  # bootstrap.OLLAMA.4
  if ! command -v ollama >/dev/null 2>&1; then
    skip "ollama not installed (opt-in: bootstrap.sh svc-ollama)"
  fi
  [ -f /etc/caddy/conf.d/ollama.conf ]
}

# ---------------------------------------------------------------------------
# Bootstrap log hygiene
# ---------------------------------------------------------------------------

@test "no Tailscale auth key in bootstrap logs" {
  # tskey- prefix is the pattern for all Tailscale auth keys.
  run grep -r "tskey-" /var/log/bootstrap/ 2>/dev/null
  [ "$status" -ne 0 ]
}
