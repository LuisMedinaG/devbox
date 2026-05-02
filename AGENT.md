# Agent Context

Personal cloud dev box on Hetzner (Ubuntu 24.04). Bootstrap scripts provision a full dev environment with Claude Code, Docker, Tailscale SSH, and Mosh.

## Repo layout

```
bootstrap/
  bootstrap.sh    Entry point; runs roles in order or a named subset
  lib/common.sh   Helpers: log/warn/die, once, ensure_line, ensure_kv,
                  enable_service (systemctl), reload_sshd, as_user, apt_install
  roles/          00-system  10-user  20-hardening  30-tailscale  40-dev-tools
                  50-shell   60-langs  70-claude-code  80-docker  90-backups
  config/         ssh-authorized-keys  tmux.conf
```

## Key constraints

- **Hetzner has full systemd** — use `systemctl` directly. `enable_service` is a thin wrapper around `systemctl enable --now`.
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_FIREWALL=0` (legacy `SKIP_UFW` still works).
- **Tailscale**: hostname `hetzner-devbox`, IP `100.118.147.126`, tailnet `betousky01@`.
- **iOS access**: Tailscale + Terminus with Mosh enabled; Mosh installed via role 40.
- **ufw is active** — SSH (22) and Mosh UDP (60000–61000) are open. Add new service ports via ufw in the relevant role.

## Roles summary

| Role | What it does |
|------|-------------|
| 00-system | timezone, 2 GB swap at `/swapfile`, sysctl |
| 10-user | create `luis`, passwordless sudo, SSH keys, loginctl linger |
| 20-hardening | harden sshd, ufw (allow SSH + Mosh), fail2ban |
| 30-tailscale | install + `tailscale up --ssh` |
| 40-dev-tools | git, tmux, zsh, ripgrep, fzf, btop, python3, mosh |
| 50-shell | zsh default, starship, tmux config, .zshrc |
| 60-langs | Node (fnm → `~/.fnm`), uv, Rust, Go |
| 70-claude-code | `npm install -g @anthropic-ai/claude-code`; run `claude` as `luis` to auth |
| 80-docker | Docker CE, `/srv/stacks` |
| 90-backups | restic skeleton (activation is manual) |

## Editing guidelines

- Bootstrap is the source of truth for host state. Don't configure things outside of it.
- New services: add an `enable_service <name>` call in the relevant role.
- New firewall ports: add `ufw allow <port>` in 20-hardening or the relevant role.
- Re-run bootstrap at any time — all roles are idempotent via the `once` helper.
