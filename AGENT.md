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
  config/         ssh-authorized-keys.example  tmux.conf
                  (real ssh-authorized-keys is gitignored; copy from .example)
```

## Division of responsibility

This repo is a **system provisioner** — it runs as root and owns everything at the OS/package layer. It does not own config files in `~`.

| Layer | Repo | What it owns |
|---|---|---|
| System | **devbox** (this repo) | apt packages, users, SSH/firewall/network, runtimes, services |
| User config | **dotfiles** (`LuisMedinaG/.dotfiles`, via yadm) | `.zshrc`, `.zshenv`, `.config/tmux/`, `.gitconfig`, nvim, plugins |

**Handoff sequence:**
1. `bash bootstrap.sh` (root) — provisions machine, installs yadm
2. Role 50 writes `~/.zshrc.local` with machine-specific PATH entries (fnm, cargo, go) — not tracked by yadm
3. `su - luis` → `yadm clone git@github.com:LuisMedinaG/.dotfiles.git` → `yadm bootstrap`
4. Dotfiles own all config from here. `~/.zshrc.local` persists across yadm operations.

**Rule:** Bootstrap must never write config into files that dotfiles owns (`.zshrc`, `.zshenv`, `.gitconfig`, etc.). Machine-specific shell entries belong in `~/.zshrc.local` or `~/.zshenv.local`.

## Key constraints

- **Hetzner has full systemd** — use `systemctl` directly. `enable_service` is a thin wrapper around `systemctl enable --now`.
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_FIREWALL=0` (legacy `SKIP_UFW` still works).
- **Tailscale**: machine name and tailnet are user-specific. Resolve via `tailscale status` on the host or your tailnet admin console.
- **iOS access**: Tailscale + Terminus with Mosh enabled; Mosh installed via role 40.
- **ufw is active** — SSH (22) and Mosh UDP (60000–61000) are open. Add new service ports via ufw in the relevant role.

## Roles summary

| Role | What it does |
|------|-------------|
| 00-system | timezone, 2 GB swap at `/swapfile`, sysctl |
| 10-user | create `luis`, passwordless sudo, SSH keys, loginctl linger |
| 20-hardening | harden sshd, ufw (allow SSH + Mosh), fail2ban |
| 30-tailscale | install + `tailscale up --ssh` |
| 35-gpu | NVIDIA driver + CDI; no-op on CPU hosts (`GPU_PROFILE=none`) |
| 40-dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 45-agent-sandbox | rootless Podman + `agent` system user (no sudo) |
| 50-shell | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60-langs | Node (fnm → `~/.fnm`), uv, Rust, Go |
| 70-claude-code | builds agent container image; no host claude binary |
| 80-docker | rootless Podman config; optional hardened Docker (`INSTALL_DOCKER=1`) |
| 90-backups | restic skeleton (activation is manual) |

## Editing guidelines

- Bootstrap is the source of truth for host state. Don't configure things outside of it.
- New services: add an `enable_service <name>` call in the relevant role.
- New firewall ports: add `ufw allow <port>` in 20-hardening or the relevant role.
- Re-run bootstrap at any time — all roles are idempotent via the `once` helper.
