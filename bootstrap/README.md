# bootstrap

Idempotent setup script for fresh Ubuntu 24.04 hosts.

## Usage

On a fresh host as root:

```bash
git clone https://github.com/LuisMedinaG/devbox.git ~/projects/devbox
cd ~/projects/devbox/bootstrap

# Run full bootstrap
bash bootstrap.sh

# Or a subset (all roles are idempotent):
bash bootstrap.sh 10-user 40-dev-tools 50-shell 60-langs 70-claude-code

# With Tailscale auth key (see below)
TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh
```

## Tailscale auth key

Get one at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) → **Generate auth key**
- **Reusable**: yes — **Ephemeral**: no

## SSH keys

Role 10 copies SSH keys to `~luis/.ssh/authorized_keys`. It uses, in order:

1. `config/ssh-authorized-keys` if present (gitignored, never committed)
2. `/root/.ssh/authorized_keys` — injected by Hetzner when the server is created with `--ssh-key`

For Hetzner hosts no manual step is needed. For other providers, copy the template and add your key:

```bash
cp config/ssh-authorized-keys.example config/ssh-authorized-keys
cat ~/.ssh/id_ed25519.pub >> config/ssh-authorized-keys
```

## Roles

| # | Role | What it does |
|---|------|--------------|
| 00 | system | timezone, 2 GB swap, sysctl tweaks |
| 10 | user | create `luis`, narrow sudo allowlist, SSH keys |
| 20 | hardening | harden sshd, ufw (SSH + Mosh), fail2ban |
| 30 | tailscale | install + `tailscale up --ssh` |
| 35 | gpu | NVIDIA driver + CDI (no-op on CPU hosts) |
| 40 | dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 45 | agent-sandbox | rootless Podman + `agent` system user (no sudo) |
| 50 | shell | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60 | langs | Node (fnm), Python (uv), Rust, Go |
| 70 | claude-code | builds agent container image with Claude Code inside |
| 80 | docker | rootless Podman config; optional hardened Docker (`INSTALL_DOCKER=1`) |
| 90 | backups | restic skeleton (activation is manual) |

## After bootstrap — deploy dotfiles

```bash
su - luis

# Deploy dotfiles (yadm installed by role 40)
yadm clone git@github.com:LuisMedinaG/.dotfiles.git
yadm bootstrap

# Authenticate Claude Code
claude

tmux new -s work
```

`~/.zshrc.local` (written by role 50, not tracked by yadm) holds machine-specific PATH
entries for fnm, cargo, and Go. It survives `yadm clone` automatically.

## Helpers (`lib/common.sh`)

- `ensure_line` — append-if-missing to a file
- `ensure_kv` — replace-or-append a `key value` directive
- `apt_update_once` — caches `apt-get update` for 60 minutes
- `download_verify <url> <dest> <sha256>` — download with hash check (no unverified installs)
- `as_user <cmd>` — run a command as `$USERNAME`
- `enable_service <name>` — `systemctl enable --now`
