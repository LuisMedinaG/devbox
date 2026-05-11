# AGENTS.md — devbox

Personal cloud dev box on Hetzner (Ubuntu 24.04). Bootstrap scripts provision a full dev environment with Claude Code, Podman, Tailscale SSH, and Mosh.

## Key commands

```bash
# Run full bootstrap (on the server, as root)
# USERNAME is auto-detected from $SUDO_USER; override explicitly if needed
sudo ./bootstrap/bootstrap.sh
sudo USERNAME=alice ./bootstrap/bootstrap.sh   # explicit override

# Run with a named profile (see PROFILES in bootstrap.sh)
sudo PROFILE=base ./bootstrap/bootstrap.sh     # minimal: system + user + hardening + tailscale + firewall
sudo PROFILE=media ./bootstrap/bootstrap.sh    # base + Caddy reverse proxy

# Run a single role
sudo ./bootstrap/bootstrap.sh 40-dev-tools

# Run post-bootstrap assertions (on the server)
bats tests/e2e.bats

# Full provision + bootstrap from your Mac — single command
# (cloud-init clones the repo and runs bootstrap.sh on first boot)
cd terraform && terraform apply
```

## Repo layout

```
bootstrap/
  bootstrap.sh       Entry point — runs roles in order or a named subset
  lib/common.sh      Helpers: log/warn/die, ensure_line,
                     source_versions, detect_arch,
                     enable_service, reload_sshd, as_user, apt_install,
                     apt_update_once, download_verify
  roles/             One script per role, executed in filename order
  config/
    versions.conf    Pinned versions + sha256 for every downloaded binary
    ssh-authorized-keys.example

terraform/
  main.tf            Hetzner server + Tailscale auth-key + device cleanup resources
  cloud-init.yaml.tpl First-boot template that runs bootstrap.sh with vars injected
  scripts/           tailscale-device.sh — shared by pre-flight + destroy cleanup
features/devbox/     Spec files (*.feature.yaml) with ACIDs
tests/e2e.bats       Post-bootstrap assertions — run on the host, not Mac
```

## Profiles

Profiles are named role sets defined in `bootstrap.sh` as the `PROFILES` associative array.
Default: `devbox`. Explicit role args bypass the profile entirely.

| Profile | Roles | Use case |
|---|---|---|
| `devbox` | 00 → 80 (full stack) | Default — dev environment with runtimes, Claude Code, dotfiles |
| `base` | 00, 10, 20, 30, 31 | Minimal — OS, user, hardening, Tailscale, firewall |
| `media` | base + 43-caddy | Base + Caddy reverse proxy for Plex/Jellyfin/etc. |

To add a profile, add an entry to the `PROFILES` map in `bootstrap.sh`.
New profiles should reference existing roles — don't create roles that duplicate another profile's purpose.

## Division of responsibility

| Layer | Owns |
|---|---|
| `terraform/` | Hetzner server resource, Tailscale auth-key + device lifecycle, first-boot orchestration via cloud-init `user_data` — no OS state |
| `bootstrap/` | apt packages, users, SSH/firewall/network, runtimes, services — all OS state |
| dotfiles (your repo via yadm, set `DOTFILES_REPO`) | `.zshrc`, `.zshenv`, `.gitconfig`, nvim, tmux config |

**Bootstrap must never write to files dotfiles owns.** Machine-specific shell entries go in `~/.zshrc.local` or `~/.zshenv.local` (not tracked by yadm).

## Roles

| Role | What it does |
|---|---|
| `00-system` | timezone, 2 GB swap, sysctl, auto-upgrades |
| `10-user` | create `$USERNAME`, narrow sudo allowlist, SSH keys, loginctl linger |
| `20-hardening` | harden sshd, fail2ban — **no UFW**, public SSH stays open for recovery |
| `30-tailscale` | install + `tailscale up --ssh` |
| `31-firewall` | UFW — runs after Tailscale; restricts port 22 to CGNAT only when Tailscale is connected |
| `40-dev-tools` | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm, pipx |
| `42-docker` | rootless Podman for `$USERNAME`; user is NOT in docker group; `podman-compose` + `docker-compose` shim for compose-based Dev Containers |
| `43-caddy` | Caddy reverse proxy — installs from official apt repo, base Caddyfile with `/health` endpoint, `conf.d/` include pattern for service snippets, opens ports 80 + 443 |
| `50-shell` | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| `60-langs` | Node (fnm), uv, Bun, Rust, Go — all sha256-pinned via `versions.conf` |
| `70-claude-code` | `npm install -g @anthropic-ai/claude-code` + claude-mem MCP |
| `80-dotfiles` | yadm clone + bootstrap as `$USERNAME`; skipped if `DOTFILES_REPO` is unset |

### Optional service roles (`svc-*`)

Service roles are opt-in and not in the default sequence. Run one standalone with:

```bash
sudo ./bootstrap/bootstrap.sh svc-ollama
```

| Role | What it does |
|---|---|
| `svc-ollama` | Ollama local LLM server — sha256-pinned binary, dedicated system user, systemd service on `0.0.0.0:11434`, Caddy snippet template at `conf.d/ollama.conf` |

**Convention for new service roles:**

1. Name the file `roles/svc-<name>.sh`.
2. Install the service binary or compose setup via `download_verify` or an official signed apt repo — never `curl | sh`.
3. Create a dedicated system user (`useradd -r`) if the upstream service recommends one.
4. Write a systemd unit to `/etc/systemd/system/<name>.service` and enable with `enable_service`.
5. Store persistent data under `/var/lib/<name>/` owned by the service user.
6. Drop a Caddy snippet at `/etc/caddy/conf.d/<name>.conf` — active or commented-out template.
7. Guard all steps with idempotency checks (`command -v`, `id`, `[[ ! -f ]]`).
8. Add version + sha256 to `config/versions.conf` for any downloaded binary.
9. Add ACID-referenced assertions to `tests/e2e.bats` with a `skip` guard when the service is not installed.

## Constraints

- **All roles are idempotent** — safe to re-run. Use `ensure_line`, `command -v` guards, never raw appends.
- **Role cache** — full default runs skip roles whose script (+ `common.sh`) hash is unchanged since last success. Cache lives in `/var/lib/bootstrap/cache/`. Explicit role args bypass it entirely. To force-re-run a specific role: `bash bootstrap.sh <role>` or `rm /var/lib/bootstrap/cache/<role>.sha256`.
- **UFW ordering** — `31-firewall` must run after `30-tailscale` or port 22 closes before the overlay is up.
- **No `curl | sh`** — all third-party binaries are verified with `download_verify <url> <dest> <sha256>` before execution. Add new tools to `versions.conf`.
- **Bootstrap defaults**: `USERNAME` auto-detected from `$SUDO_USER` (override explicitly if needed), `TIMEZONE=America/Mexico_City`, `MACHINE_NAME=devbox`, `TS_TAG=tag:${MACHINE_NAME}`, `SKIP_FIREWALL=0`, `SKIP_SSH_HARDENING=0`, `DEV_MODE=0`.
- **`DEV_MODE=1`** (or Terraform `dev_mode = true`): umbrella escape hatch that sets `SKIP_FIREWALL=1` and `SKIP_SSH_HARDENING=1` so public root SSH stays usable. fail2ban still runs. **Never leave on for a long-lived host** — Hetzner IPs are scanned within minutes.
- **Logs**: `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log` — check here first on failure. When provisioned via Terraform, also check `/var/log/cloud-init-output.log` for first-boot orchestration output.
- **Cloud-init secrets policy**: `TS_AUTHKEY` is OK to embed in `user_data` (1-hour expiry). `USER_PASSWORD` is intentionally never embedded — Hetzner stores `user_data` for the lifetime of the server, so long-lived secrets must be set manually post-bootstrap.

## Editing guidelines

- New apt packages → `apt_install` in the relevant role.
- New third-party binary → add version + sha256 to `config/versions.conf`, use `download_verify`.
- New services → `enable_service <name>` in the relevant role.
- New firewall ports → `ufw allow <port>` in `31-firewall` or the relevant role.
- Post-bootstrap state changes → update `tests/e2e.bats` to assert the new invariant.
- Spec changes → update `features/devbox/*.feature.yaml` before changing code; reference full ACIDs in comments. Run `/update-spec` to audit the feature file against the current code state.
- Doc changes → run `/update-docs` to audit `CLAUDE.md` and `AGENTS.md` against the current role scripts after meaningful role changes.
