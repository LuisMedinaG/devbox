# Agent Context

Personal cloud dev box on Hetzner (Ubuntu 24.04). Bootstrap scripts provision a full dev environment with Claude Code, Docker, Tailscale SSH, and Mosh.

## Repo layout

```
terraform/        Optional declarative provisioning of the Hetzner server.
                  Alternative to `hcloud server create` (both documented in
                  README.md). References pre-existing Hetzner SSH keys via
                  data source rather than uploading them.

bootstrap/
  bootstrap.sh    Entry point; runs roles in order or a named subset
  lib/common.sh   Helpers: log/warn/die, once, ensure_line, ensure_kv,
                  enable_service (systemctl), reload_sshd, as_user, apt_install
  roles/          00-system  10-user  20-hardening  30-tailscale
                   31-firewall  40-dev-tools  42-docker  50-shell  60-langs
  config/         ssh-authorized-keys.example  tmux.conf
                  (real ssh-authorized-keys is gitignored; copy from .example)

tests/
  e2e.bats        Post-bootstrap assertions: SSH/UFW/fail2ban posture,
                  user/sudoers separation, Podman rootless, restic skeleton.
                  Run on the host or via run-local.sh.
  run-local.sh    Multipass-based runner: launches Ubuntu 24.04 VM,
                  bootstraps, runs bats, tears down.
```

## Division of responsibility

This repo is a **system provisioner** — it runs as root and owns everything at the OS/package layer. It does not own config files in `~`.

| Layer | Repo | What it owns |
|---|---|---|
| Infrastructure | **devbox** (this repo, `terraform/`) | Hetzner server, SSH keys (referenced, not uploaded) |
| System | **devbox** (this repo, `bootstrap/`) | apt packages, users, SSH/firewall/network, runtimes, services, agent sandbox |
| User config | **dotfiles** (`LuisMedinaG/.dotfiles`, via yadm) | `.zshrc`, `.zshenv`, `.config/tmux/`, `.gitconfig`, nvim, plugins |

**Handoff sequence:**
0. (Optional) `terraform apply` from `terraform/` — provisions the Hetzner server. Same end state as `hcloud server create`; pick whichever is documented in README.md.
1. `bash bootstrap.sh` (root) — provisions machine, installs yadm
2. Role 50 writes `~/.zshrc.local` with machine-specific PATH entries (fnm, cargo, go) — not tracked by yadm
3. `su - luis` → `yadm clone git@github.com:LuisMedinaG/.dotfiles.git` → `yadm bootstrap`
4. Dotfiles own all config from here. `~/.zshrc.local` persists across yadm operations.

**Rule:** Bootstrap must never write config into files that dotfiles owns (`.zshrc`, `.zshenv`, `.gitconfig`, etc.). Machine-specific shell entries belong in `~/.zshrc.local` or `~/.zshenv.local`.

## Logs

Bootstrap writes a timestamped log of all role output (stdout + stderr) to `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log`. Check there first when troubleshooting a failed run.

## Key constraints

- **Hetzner has full systemd** — use `systemctl` directly. `enable_service` is a thin wrapper around `systemctl enable --now`.
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_FIREWALL=0` (legacy `SKIP_UFW` still works).
- **Tailscale**: machine name and tailnet are user-specific. Resolve via `tailscale status` on the host or your tailnet admin console.
- **iOS access**: Tailscale + Terminus with Mosh enabled; Mosh installed via role 40.
- **ufw is active** — role 31-firewall runs after Tailscale to prevent lock-out: port 22 stays open on public IP until Tailscale overlay is confirmed connected. Mosh UDP (60000–61000) is open. Port 22 is restricted to Tailscale CGNAT (`100.64.0.0/10`) only when a Tailscale connection exists. Add new service ports via ufw in the relevant role.

## Roles summary

| Role | What it does |
|------|-------------|
| 00-system | timezone, 2 GB swap at `/swapfile`, sysctl |
| 10-user | create `luis`, narrow sudo allowlist, SSH keys, loginctl linger |
| 20-hardening | harden sshd, fail2ban — **no UFW here**, public SSH stays open for recovery |
| 30-tailscale | install + `tailscale up --ssh` |
| 31-firewall | UFW — runs after Tailscale; restricts port 22 to CGNAT only if Tailscale is connected |
| 40-dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 42-docker | rootless Podman for `$USERNAME`; user is NOT in docker group |
| 50-shell | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60-langs | Node (fnm → `~/.fnm`), uv, Bun, Rust, Go |

## Claude Code

Install as `luis` after dotfiles are deployed, then use the built-in sandbox:

```bash
npm install -g @anthropic-ai/claude-code
claude --sandbox
```

## Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml` files. Each requirement has a stable ID called an ACID (e.g. `bootstrap.HARDENING.1`).

**Rules:**
- Write or update the spec first, before changing code.
- Reference ACIDs in code comments and test names co-located with the behavior they implement. Full ACID only — never partial IDs or lists.
- Aim for at least one test block per ACID.
- Never renumber requirements; use `deprecated: true` instead of deleting them.
- Run `npx @acai.sh/cli skill` to load the full acai workflow into context before planning implementation work.

**Push specs to the dashboard:**
```bash
npx @acai.sh/cli push --all   # requires ACAI_API_TOKEN in .env or environment
```

**Rotate the GitHub Actions secret:**
```bash
gh secret set ACAI_API_TOKEN --body "$ACAI_API_TOKEN" --repo LuisMedinaG/devbox
```

## Editing guidelines

- Bootstrap is the source of truth for host state. Don't configure things outside of it.
- Terraform is the source of truth for the Hetzner server resource itself. Don't add OS-level config there — it belongs in bootstrap.
- New services: add an `enable_service <name>` call in the relevant role.
- New firewall ports: add `ufw allow <port>` in 20-hardening or the relevant role.
- Re-run bootstrap at any time — all roles are idempotent.
- After changes that affect post-bootstrap state, update `tests/e2e.bats` to assert the new invariant.
