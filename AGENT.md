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
  roles/          00-system  10-user  20-hardening  30-tailscale  40-dev-tools
                  42-docker  45-agent-sandbox  50-shell  60-langs  70-claude-code  90-backups
  config/         ssh-authorized-keys.example  tmux.conf
                  (real ssh-authorized-keys is gitignored; copy from .example)

tests/
  e2e.bats        Post-bootstrap assertions: SSH/UFW/fail2ban posture,
                  user/sudoers separation, sandbox isolation, agent-run
                  escape rejection. Run on the host or via run-local.sh.
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

**Agent sandbox boundary:** Claude Code runs only inside the `devbox-claude-code`
container, launched via `sudo agent-run <workspace>`. The host has no `claude`
binary on PATH. The wrapper accepts only `-e KEY=VALUE`; all other podman flags
are rejected to prevent sandbox escape. See role `45-agent-sandbox` for details.

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
- **ufw is active** — Mosh UDP (60000–61000) is open. Port 22 is restricted to Tailscale CGNAT (`100.64.0.0/10`) by role 30 after enrollment; public SSH is closed. Add new service ports via ufw in the relevant role.

## Roles summary

| Role | What it does |
|------|-------------|
| 00-system | timezone, 2 GB swap at `/swapfile`, sysctl |
| 10-user | create `luis`, passwordless sudo, SSH keys, loginctl linger |
| 20-hardening | harden sshd, ufw (allow SSH + Mosh), fail2ban |
| 30-tailscale | install + `tailscale up --ssh`; restricts port 22 to CGNAT after enrollment |
| 35-gpu | NVIDIA driver + container toolkit + CDI spec at `/etc/cdi/nvidia.yaml`; auto-skipped if `lspci` finds no NVIDIA device |
| 40-dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 42-docker | rootless Podman config for `$USERNAME`; optional hardened Docker (`INSTALL_DOCKER=1`) |
| 45-agent-sandbox | `agent` system user (no sudo, no docker group); `agent-run` wrapper at `/usr/local/bin/agent-run`; smoke test at `/usr/local/libexec/agent-sandbox-smoke-test.sh` |
| 50-shell | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| 60-langs | Node (fnm → `~/.fnm`), uv, Rust, Go |
| 70-claude-code | builds agent container image; no host claude binary |
| 42-docker | rootless Podman config; optional hardened Docker (`INSTALL_DOCKER=1`) |
| 90-backups | restic skeleton (activation is manual) |

## Agent sandbox usage

```bash
sudo agent-run <workspace>                # workspace persists at /srv/workspaces/<workspace>
sudo agent-run <workspace> -e KEY=VALUE   # only -e flags are accepted
```

Hardening flags applied unconditionally by the wrapper: `--cap-drop=ALL`,
`--security-opt=no-new-privileges`, `--read-only`, `--userns=keep-id`,
`--network=agent-net` (isolated bridge), tmpfs for `/tmp`, `/run`,
`~/.claude`, `~/.cache`, `~/.npm`. Workspace mounted at `/work`.

The wrapper rejects `--`, `--privileged`, `-v`, `--network`, and any
non-`-e` flags — enforced by `agent-sandbox-smoke-test.sh`.

## Editing guidelines

- Bootstrap is the source of truth for host state. Don't configure things outside of it.
- Terraform is the source of truth for the Hetzner server resource itself. Don't add OS-level config there — it belongs in bootstrap.
- New services: add an `enable_service <name>` call in the relevant role.
- New firewall ports: add `ufw allow <port>` in 20-hardening or the relevant role.
- New `agent-*.service` units: callable by `$USERNAME` via `sudo agent-service-ctl <action> <unit>` (validated wrapper, no sudoers glob).
- Sandbox flags: change them in **one** place (the heredoc inside `45-agent-sandbox.sh`). The smoke test mirrors them; keep both in sync.
- Re-run bootstrap at any time — all roles are idempotent.
- After changes that affect post-bootstrap state, update `tests/e2e.bats` to assert the new invariant.
