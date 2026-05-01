# Agent Context

Personal cloud dev box running Claude Code on Fly.io with persistent storage.
The same bootstrap also targets Hetzner VPS (Ubuntu 24.04).

## Repo layout

```
fly.toml          Fly app config — performance-2x, dfw, volume at /home, no public ports
Dockerfile        ubuntu:24.04 + tini; CMD is start.sh (keeps machine alive, starts services)
start.sh          Runs on every machine boot — starts sshd/dockerd/tailscaled if installed
bootstrap/        Idempotent setup script; works on Fly and Hetzner
  bootstrap.sh    Entry point; runs roles in order or a named subset
  lib/common.sh   Helpers: log/warn/die, once, ensure_line, ensure_kv, have_systemd,
                  enable_service (systemd-aware), reload_sshd, as_user, apt_install
  roles/          00-system  10-user  20-hardening  30-tailscale  40-dev-tools
                  50-shell   60-langs  70-claude-code  80-docker  90-backups
  config/         ssh-authorized-keys  tmux.conf
```

## Key constraints

- **No systemd on Fly** — Fly's init is PID 1; our CMD runs as a child process.
  Use `have_systemd` before any `systemctl` call. Use `enable_service <name> <bin>` instead of
  `systemctl enable --now`. Services start on boot via `start.sh`.
- **`/home` is the only persistent path** — everything else is ephemeral and reset on `fly deploy`.
  Swap file lives at `/home/swapfile`. Bootstrap markers at `/var/lib/bootstrap/` are ephemeral
  (safe — bootstrap is idempotent).
- **No public ports** — `fly ssh console` connects via Fly's 6PN (WireGuard, `fdaa::/8`).
  Tailscale SSH is the primary access method. `fly ssh console` is the fallback.
  ufw is skipped on Fly (`SKIP_UFW=1` default); enabled on Hetzner (`SKIP_UFW=0`).
- **Tailscale on both hosts** — Fly machine: `lumedina-devbox` (`100.64.54.128`).
  Hetzner machine: `devbox-hetzner` (`178.104.247.3`). Both on the `betousky01@` tailnet.
  iOS access via Tailscale app + Terminus (password auth over WireGuard).
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_UFW=1`.
  Override at call site; `SKIP_UFW=0` for Hetzner.

## Roles summary

| Role | What it does | Fly notes |
|------|-------------|-----------|
| 00-system | timezone, swap at `/home/swapfile`, sysctl | skip `software-properties-common`; use `ln -sf` for timezone |
| 10-user | create `luis`, passwordless sudo, SSH keys | `loginctl` guarded by `have_systemd` |
| 20-hardening | harden sshd, ufw, fail2ban | ufw/fail2ban skipped when `SKIP_UFW=1` |
| 30-tailscale | install + connect tailscale-ssh | `enable_service tailscaled` |
| 40-dev-tools | git, sudo, tmux, zsh, ripgrep, fzf, python3… | installs `sudo` (absent in bare image) |
| 50-shell | zsh default, starship, tmux config, .zshrc | — |
| 60-langs | Node (fnm → `~/.fnm`), uv, Rust, Go 1.23.4 | fnm installed with `--install-dir ~/.fnm` |
| 70-claude-code | `npm install -g @anthropic-ai/claude-code` | run `claude` as `luis` to auth |
| 80-docker | Docker CE, `/srv/stacks` | `enable_service docker` |
| 90-backups | restic skeleton + timer files (not enabled) | user systemd timers need systemd; use cron on Fly |

## Editing guidelines

- Add new daemons to `start.sh` with the same `[ -x /path ] && ...` guard pattern.
- New `systemctl` calls must go through `enable_service` or be guarded by `have_systemd`.
- Test changes on Fly first (faster iteration); validate on Hetzner before merging.
- Bootstrap is the source of truth for host state. Don't configure things outside of it.
