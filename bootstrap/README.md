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

## Tailscale setup

### ACL (Tailscale admin console → Access controls)

```json
{
    "groups": {
        "group:owners": ["betousky01@gmail.com"]
    },
    "tagOwners": {
        "tag:devbox": ["group:owners"]
    },
    "grants": [
        {
            "src": ["group:owners"],
            "dst": ["tag:devbox"],
            "ip":  ["*"]
        }
    ],
    "ssh": [
        {
            "action": "accept",
            "src":    ["group:owners"],
            "dst":    ["tag:devbox"],
            "users":  ["autogroup:nonroot", "root"]
        }
    ]
}
```

### Auth key

Get one at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) → **Generate auth key**

| Setting | Value |
|---|---|
| Reusable | **no** (single-use per server) |
| Ephemeral | **no** (devbox must persist after reboot) |
| Pre-approved | **yes** |
| Tags | `tag:devbox` |

Pass it to bootstrap: `TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh`

After enrollment, connect with `tailscale ssh devbox` — no SSH keys needed.

### Port 22 lockdown

Role 30 automatically restricts port 22 to the Tailscale CGNAT range (`100.64.0.0/10`) once Tailscale is connected. Public SSH is closed; traditional SSH keys remain as a fallback reachable only through the Tailscale overlay.

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
| 30 | tailscale | install + `tailscale up --ssh`; locks port 22 to CGNAT after enrollment |
| 35 | gpu | NVIDIA driver + CDI (no-op on CPU hosts) |
| 40 | dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 42 | docker | rootless Podman config; optional hardened Docker (`INSTALL_DOCKER=1`) |
| 45 | agent-sandbox | rootless Podman + `agent` system user (no sudo) |
| 50 | shell | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60 | langs | Node (fnm), Python (uv), Rust, Go |
| 70 | claude-code | builds agent container image with Claude Code inside |
| 90 | backups | restic skeleton (activation is manual) |

## Updating pinned versions (`config/versions.conf`)

All third-party binaries (Go, fnm, uv, Bun, Rust, NVIDIA, Claude Code base image) are pinned with a version + sha256. Bootstrap aborts if any hash is empty.

Use the included script to check for updates and fetch new hashes:

```bash
# Check what's outdated (dry-run, no changes)
./update-versions.sh

# Fetch new versions and rewrite versions.conf in place
./update-versions.sh --update

# Review, then commit
git diff config/versions.conf
git add config/versions.conf && git commit -m "chore: bump pinned versions"
```

Set `GITHUB_TOKEN` to avoid GitHub API rate-limiting (60 req/hr unauthenticated).

NVIDIA and the Claude Code base image (`AGENT_BASE_IMAGE`) are not automated — check [NVIDIA driver releases](https://launchpad.net/~graphics-drivers/+archive/ubuntu/ppa) and [Node Docker tags](https://hub.docker.com/_/node/tags) manually.

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

## Logs

Every run writes a timestamped log to `/var/log/bootstrap/`:

```bash
/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log
```

All stdout and stderr from every role is captured. To follow a run live:

```bash
tail -f /var/log/bootstrap/bootstrap-$(date +%Y%m%d)*.log
```

## Helpers (`lib/common.sh`)

- `ensure_line` — append-if-missing to a file
- `ensure_kv` — replace-or-append a `key value` directive
- `apt_update_once` — caches `apt-get update` for 60 minutes
- `download_verify <url> <dest> <sha256>` — download with hash check (no unverified installs)
- `as_user <cmd>` — run a command as `$USERNAME`
- `enable_service <name>` — `systemctl enable --now`
