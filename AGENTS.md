# AGENTS.md — devbox

Personal cloud dev box on Hetzner (Ubuntu 24.04). Bootstrap scripts provision a full dev environment with Claude Code, Podman, Tailscale SSH, and Mosh.

## Key commands

```bash
# Run full bootstrap (on the server, as root)
sudo USERNAME=luis ./bootstrap/bootstrap.sh

# Run a single role
sudo USERNAME=luis ./bootstrap/bootstrap.sh 40-dev-tools

# Run post-bootstrap assertions (on the server)
bats tests/e2e.bats

# Provision the Hetzner server (optional — alternative to hcloud CLI)
cd terraform && terraform apply
```

## Repo layout

```
bootstrap/
  bootstrap.sh       Entry point — runs roles in order or a named subset
  lib/common.sh      Helpers: log/warn/die, ensure_line, ensure_kv,
                     enable_service, reload_sshd, as_user, apt_install,
                     apt_update_once, download_verify
  roles/             One script per role, executed in filename order
  config/
    versions.conf    Pinned versions + sha256 for every downloaded binary
    ssh-authorized-keys.example

terraform/           Hetzner server declaration (references existing SSH keys)
features/devbox/     Spec files (*.feature.yaml) with ACIDs
tests/e2e.bats       Post-bootstrap assertions — run on the host, not Mac
```

## Division of responsibility

| Layer | Owns |
|---|---|
| `terraform/` | Hetzner server resource — no OS config here |
| `bootstrap/` | apt packages, users, SSH/firewall/network, runtimes, services |
| dotfiles (`LuisMedinaG/.dotfiles` via yadm) | `.zshrc`, `.zshenv`, `.gitconfig`, nvim, tmux config |

**Bootstrap must never write to files dotfiles owns.** Machine-specific shell entries go in `~/.zshrc.local` or `~/.zshenv.local` (not tracked by yadm).

## Roles

| Role | What it does |
|---|---|
| `00-system` | timezone, 2 GB swap, sysctl, auto-upgrades |
| `10-user` | create `luis`, narrow sudo allowlist, SSH keys, loginctl linger |
| `20-hardening` | harden sshd, fail2ban — **no UFW**, public SSH stays open for recovery |
| `30-tailscale` | install + `tailscale up --ssh` |
| `31-firewall` | UFW — runs after Tailscale; restricts port 22 to CGNAT only when Tailscale is connected |
| `40-dev-tools` | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm |
| `42-docker` | rootless Podman for `luis`; user is NOT in docker group; `podman-compose` + `docker-compose` shim for compose-based Dev Containers |
| `43-caddy` | Caddy reverse proxy — installs from official apt repo, base Caddyfile with `/health` endpoint, `conf.d/` include pattern for service snippets, opens ports 80 + 443 |
| `50-shell` | set zsh as default; write `~/.zshrc.local` with machine PATH entries |
| `60-langs` | Node (fnm), uv, Bun, Rust, Go — all sha256-pinned via `versions.conf` |
| `70-claude-code` | `npm install -g @anthropic-ai/claude-code` + claude-mem MCP |
| `80-dotfiles` | yadm clone + bootstrap as `luis` |

### Optional service roles (`svc-*`)

Service roles are opt-in and not in the default sequence. Run one standalone with:

```bash
sudo USERNAME=luis ./bootstrap/bootstrap.sh svc-ollama
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

- **All roles are idempotent** — safe to re-run. Use `ensure_line`, `ensure_kv`, and `command -v` guards, never raw appends.
- **UFW ordering** — `31-firewall` must run after `30-tailscale` or port 22 closes before the overlay is up.
- **No `curl | sh`** — all third-party binaries are verified with `download_verify <url> <dest> <sha256>` before execution. Add new tools to `versions.conf`.
- **Bootstrap defaults**: `USERNAME=luis`, `TIMEZONE=America/Mexico_City`, `SKIP_FIREWALL=0`.
- **Logs**: `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log` — check here first on failure.

## Editing guidelines

- New apt packages → `apt_install` in the relevant role.
- New third-party binary → add version + sha256 to `config/versions.conf`, use `download_verify`.
- New services → `enable_service <name>` in the relevant role.
- New firewall ports → `ufw allow <port>` in `31-firewall` or the relevant role.
- Post-bootstrap state changes → update `tests/e2e.bats` to assert the new invariant.
- Spec changes → update `features/devbox/*.feature.yaml` before changing code; reference full ACIDs in comments.
