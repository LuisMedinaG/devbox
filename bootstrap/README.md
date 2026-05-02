# bootstrap

Idempotent setup script for fresh Ubuntu 24.04 hosts. Designed to grow into a multi-host, multi-service home lab over time.

## Usage

On a fresh host as root:

```bash
git clone <this-repo> /opt/bootstrap
cd /opt/bootstrap

# 1. Create config/ssh-authorized-keys (gitignored) from the template:
#    cp config/ssh-authorized-keys.example config/ssh-authorized-keys
#    Then add your pubkey(s). Bootstrap dies if this file is missing.

# 2. Run everything:
USERNAME=luis TIMEZONE=America/Mexico_City ./bootstrap.sh

# Or run a subset (re-runnable, idempotent):
./bootstrap.sh 60-langs 70-claude-code
```

Optional: prefill Tailscale auth with `TS_AUTHKEY=tskey-...`.

## Roles

| # | Role | What it does |
|---|------|--------------|
| 00 | system | Base packages, swap, timezone, unattended upgrades |
| 10 | user | Create user, install SSH keys, passwordless sudo |
| 20 | hardening | sshd config, ufw, fail2ban |
| 30 | tailscale | Install + bring up tailscale-ssh |
| 40 | dev-tools | git, tmux, ripgrep, fd, bat, fzf, btop, age |
| 50 | shell | zsh, starship, tmux config |
| 60 | langs | Node (fnm), Python (uv), Rust, Go |
| 70 | claude-code | Install Claude Code CLI |
| 80 | docker | Docker engine + compose, `/srv/stacks` ready |
| 90 | backups | restic skeleton + systemd timer (disabled) |

## After bootstrap

```bash
ssh luis@<host>
claude         # complete Claude Code device-flow auth
tmux new -s work
```

## Adding services later

Drop compose stacks under `/srv/stacks/<service>/compose.yml` and add a `roles/1xx-<service>.sh` that templates env files and runs `docker compose up -d`.

## Idempotency

All roles are safe to re-run. Helpers in `lib/common.sh`:
- `ensure_line` — append-if-missing
- `ensure_kv` — replace-or-append directives
- `apt_update_once` — caches apt update for 60 minutes
