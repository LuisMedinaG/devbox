# Claude Code Context — devbox

Personal cloud dev box on Hetzner (Ubuntu 24.04). Bootstrap scripts provision a full dev environment with Claude Code, Podman, Tailscale SSH, and Mosh.

## Repo layout

```
terraform/        Declarative Hetzner server provisioning (alternative to hcloud CLI).
                  References pre-existing SSH keys by name, does not upload them.

bootstrap/
  bootstrap.sh    Entry point — runs roles in order or a named subset
  lib/common.sh   Helpers: log/warn/die, once, ensure_line, ensure_kv,
                  enable_service, reload_sshd, as_user, apt_install
  roles/          00-system  10-user  20-hardening  30-tailscale
                   31-firewall  40-dev-tools  42-docker  50-shell
                   60-langs  70-claude-code  80-dotfiles
  config/         ssh-authorized-keys.example  versions.conf  tmux.conf

features/devbox/  Spec files (*.feature.yaml) with ACIDs
tests/
  e2e.bats        Post-bootstrap assertions
  run-local.sh    Multipass-based local VM runner
```

## Division of responsibility

| Layer | Repo | Owns |
|---|---|---|
| Infrastructure | devbox (`terraform/`) | Hetzner server, SSH keys (referenced, not uploaded) |
| System | devbox (`bootstrap/`) | apt packages, users, SSH/firewall/network, runtimes, services |
| User config | dotfiles (`LuisMedinaG/.dotfiles`, via yadm) | `.zshrc`, `.zshenv`, `.config/tmux/`, `.gitconfig`, nvim, plugins |

**Handoff sequence:**
1. `bash bootstrap.sh` (root) — provisions machine
2. Role 50 writes `~/.zshrc.local` with machine PATH entries (fnm, cargo, go) — not tracked by yadm
3. Role 80 runs `yadm clone` + `yadm bootstrap` as luis; if it fails (GitHub SSH not configured), run manually
4. Dotfiles own all config from here

**Rule:** Bootstrap must never write to files dotfiles owns (`.zshrc`, `.zshenv`, `.gitconfig`). Machine-specific shell entries go in `~/.zshrc.local` or `~/.zshenv.local`.

## Roles summary

| Role | What it does |
|------|-------------|
| 00-system | timezone, 2 GB swap, sysctl |
| 10-user | create `luis`, narrow sudo allowlist, SSH keys, loginctl linger |
| 20-hardening | harden sshd, fail2ban — no UFW here |
| 30-tailscale | install + `tailscale up --ssh` |
| 31-firewall | UFW — runs after Tailscale; restricts port 22 to CGNAT only if Tailscale is connected |
| 40-dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm |
| 42-docker | rootless Podman for `$USERNAME`; user is NOT in docker group |
| 50-shell | zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60-langs | Node (fnm), uv, Bun, Rust, Go — sha256-pinned via `config/versions.conf` |
| 70-claude-code | `npm install -g @anthropic-ai/claude-code` |
| 80-dotfiles | yadm clone + bootstrap (runs as $USERNAME) |

## Key constraints

- **Idempotent** — all roles use `once`/`ensure_line`/`ensure_kv` guards; safe to re-run
- **Hetzner has full systemd** — use `systemctl` directly via `enable_service`
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_FIREWALL=0`
- **UFW ordering** — 31-firewall intentionally runs after 30-tailscale to prevent SSH lockout
- **Logs** — `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log`; check there first when troubleshooting

## Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml`. Each requirement has a stable ACID (e.g. `bootstrap.HARDENING.1`).

- Write or update the spec before changing code
- Reference ACIDs in code comments and test names — full ACID only, never partial
- Never renumber requirements; use `deprecated: true` instead of deleting
- Run `npx @acai.sh/cli skill` before planning implementation work to load the full acai workflow

## Editing guidelines

- Bootstrap is the source of truth for host state — don't configure things outside of it
- Terraform is the source of truth for the Hetzner resource — no OS-level config there
- New services: add `enable_service <name>` in the relevant role
- New firewall ports: add `ufw allow <port>` in 31-firewall or the relevant role
- After post-bootstrap state changes, update `tests/e2e.bats` to assert the new invariant
