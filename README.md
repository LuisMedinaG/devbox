# devbox

Personal cloud dev box running Claude Code on Hetzner. Persistent tmux sessions, survives disconnects. Access via Tailscale SSH or Mosh.

- **Machine**: CX23 (2 vCPU, 4 GB RAM, 40 GB SSD), location `nbg1`
- **OS**: Ubuntu 24.04
- **Access**: Tailscale SSH (primary), Mosh (mobile)

---

## Hetzner setup

Two ways to provision the host — pick one. Both end up with the same machine.

- **Terraform** (`terraform/`) — declarative, easy to recreate or spin up variants.
- **`hcloud` CLI** — one-shot commands, no state file.

Get an API token first: https://console.hetzner.com/projects/<project-id>/security/tokens

### Option A: Terraform

Prerequisite: at least one SSH public key already uploaded to your Hetzner project. Check with `hcloud ssh-key list`; upload one with `hcloud ssh-key create --name <name> --public-key "$(cat ~/.ssh/id_ed25519.pub)"`. The Terraform module references existing keys by name rather than uploading them, so it composes cleanly with whatever you already have in the project.

```bash
brew install terraform

# Authenticate — same token you used for `hcloud`. Two options:
export HCLOUD_TOKEN=your-token-here     # preferred: token stays out of files
# or paste it into terraform.tfvars (gitignored) below.

cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: list the SSH key names (from `hcloud ssh-key list`)
# you want authorized on the box, plus any region/type overrides.

terraform init
terraform apply
terraform output ipv4    # public IP of the devbox
```

To tear it down: `terraform destroy`. State lives in `terraform/terraform.tfstate` (gitignored) — back it up if you care about reproducibility across machines, or migrate to a remote backend.

> **Region note:** `cx`-line server types (Intel) are EU-only on some accounts. For `ash`/`hil`/`sin`, try `cpx21` (AMD) or `cax21` (ARM) instead. Verify with `hcloud server-type describe <type>`.

### Option B: hcloud CLI

```bash
brew install hcloud
hcloud context create devbox     # paste the API token

# Upload your SSH key if not already in Hetzner
hcloud ssh-key create --name macbook --public-key "$(cat ~/.ssh/id_ed25519.pub)"

# Create server — CX23: 2 vCPU, 4 GB RAM, 40 GB SSD
hcloud server create \
  --name devbox \
  --type cx23 \
  --image ubuntu-24.04 \
  --location nbg1 \
  --ssh-key macbook

hcloud server list    # get the IP
```

### Server lifecycle

Day-to-day power operations work the same regardless of how you provisioned. Use `hcloud` for these — Terraform doesn't model power state:

```bash
hcloud server list
hcloud server reboot devbox
hcloud server poweroff devbox
hcloud server poweron devbox
hcloud server delete devbox      # permanent — back up first
```

> If you provisioned with Terraform, prefer `terraform destroy` over `hcloud server delete` so state stays in sync.

### Recreating the box

When you nuke and re-provision, two things in Tailscale don't auto-clean:

1. The old `devbox` node entry in your tailnet admin console — it'll auto-expire eventually, but remove it manually at https://login.tailscale.com/admin/machines if you want the hostname free immediately.
2. The previous auth key (if reusable) is still valid — generate a fresh one for the new box at https://login.tailscale.com/admin/settings/keys.

Then re-run the bootstrap on the new host as documented below; nothing in the Terraform module needs to change for Tailscale.

---

## Bootstrap

Runs on a fresh host as root. Idempotent — safe to re-run.

### On the machine

```bash
# Install git (bare ubuntu image only)
apt-get update -y && apt-get install -y git

git clone https://github.com/LuisMedinaG/devbox.git ~/projects/devbox
cd ~/projects/devbox/bootstrap

# TS_AUTHKEY is optional — connects Tailscale unattended so you don't need
# a second SSH login. Get one at:
# login.tailscale.com/admin/settings/keys → Generate auth key (Reusable: yes, Ephemeral: no)
TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh

# Without it, bootstrap still completes. Connect Tailscale manually after:
#   sudo tailscale up --ssh
```

### Logs

Every run saves a timestamped log to `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log` — all role output (stdout + stderr). Check there first when troubleshooting.

### Roles

| # | Role | What it does |
|---|------|-------------|
| 00 | system | timezone, 2 GB swap, sysctl tweaks, unattended-upgrade auto-reboot, bootstrap log rotation |
| 10 | user | create `luis`, narrow sudo allowlist (`agent-run`, `agent-service-ctl`, `apt-get update`), SSH keys |
| 20 | hardening | harden sshd, ufw, fail2ban with sshd jail enabled |
| 30 | tailscale | install + connect tailscale-ssh; clears `TS_AUTHKEY` from env after use |
| 35 | gpu | NVIDIA driver + container toolkit + CDI spec so Podman can attach GPUs via `--device nvidia.com/gpu=all`; auto-skipped on CPU-only hosts |
| 40 | dev-tools | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, python3, mosh, yadm |
| 42 | docker | rootless Podman config; optional hardened Docker |
| 45 | agent-sandbox | `agent` system user (no sudo, no docker group); `agent-run` wrapper; sandbox smoke test |
| 50 | shell | set zsh as default shell; write `~/.zshrc.local` with machine PATH entries |
| 60 | langs | Node (fnm), Python (uv), Bun, Rust, Go — all sha256-pinned via `config/versions.conf` |
| 70 | claude-code | builds `devbox-claude-code` image; UID/GID matched to host `agent` user via build args |
| 90 | backups | restic skeleton (activation is manual) |

### After bootstrap — deploy dotfiles

Bootstrap provisions the system. Dotfiles configure the user environment. Run these as `luis`:

```bash
su - luis

# Deploy dotfiles (yadm was installed by role 40)
yadm clone git@github.com:LuisMedinaG/.dotfiles.git

# Run dotfiles bootstrap phases (Homebrew on macOS; Linux tooling on Linux)
yadm bootstrap

# Start a persistent work session
tmux new -s work
```

`~/.zshrc.local` (written by role 50, not tracked by yadm) holds machine-specific PATH
entries for fnm, cargo, and Go. It survives `yadm clone` and is sourced automatically
by `.zshrc`.

---

## Running Claude Code in the agent sandbox

Claude is **not** installed on the host PATH. Every invocation runs inside a rootless
Podman container under a dedicated `agent` system user (no sudo, no docker group),
launched via the `agent-run` wrapper. Workspaces persist at `/srv/workspaces/<name>`.

```bash
# First time: workspace is created on first run
sudo agent-run my-project

# Pass environment variables (the only flag the wrapper accepts)
sudo agent-run my-project -e ANTHROPIC_API_KEY=sk-...
```

Sandbox guarantees (enforced by the wrapper, not caller-controlled):

- `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--read-only` rootfs
- `--userns=keep-id` — container UID matches the host `agent` user
- Isolated `agent-net` Podman network; no access to host loopback or other containers
- tmpfs for `/tmp`, `/run`, `~/.claude`, `~/.cache`, `~/.npm`
- Workspace mounted at `/work` (the only host path the container sees)

The wrapper rejects all extra podman flags (`--privileged`, `-v /:/host`, `--network=host`,
`--`, etc.). Verify the sandbox after bootstrap:

```bash
sudo /usr/local/libexec/agent-sandbox-smoke-test.sh
```

To manage agent-related systemd units (without granting blanket sudo):

```bash
sudo agent-service-ctl restart agent-foo.service
```

---

## Access

### Mac `~/.ssh/config`

```
Host devbox
  HostName <devbox-tailscale-name-or-ip>
  User luis
  IdentityFile ~/.ssh/id_ed25519
```

> Use the Tailscale IP (visible in `tailscale status`) until MagicDNS resolves the hostname.

### iOS — Terminus + Mosh

1. Install **Tailscale** from the App Store — sign in with the same account
2. In **Terminus**: add a new host
   - **Host**: your devbox Tailscale IP (from `tailscale status`)
   - **User**: `luis`
   - **Use Mosh**: enabled (leave the mosh-server command at default)
   - **Auth**: SSH key (password auth is disabled by hardening; add your key in Terminus → SSH.id)

Mosh handles roaming between WiFi and cellular without dropping the session.

---

## VS Code SSH Remote + Dev Containers

Connect VS Code on your Mac to the devbox and open repos in isolated Docker containers — same experience as GitHub Codespaces, self-hosted.

### Mac prerequisites

1. Install the **Remote - SSH** extension in VS Code.
2. Install the **Dev Containers** extension in VS Code.
3. Tailscale running and logged into the same account.

### Host prerequisites (handled by bootstrap)

- Rootless Podman (configured by role 42) is the default container runtime.
- Docker CE is installed only when bootstrap runs with `INSTALL_DOCKER=1`. The default is `0`; the interactive user is **not** added to the `docker` group regardless.
- VS Code CLI is installed to `~/.local/bin/code`:

```bash
curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
  | tar -xz -C ~/.local/bin
```

### Workflow

```
1. VS Code on Mac → Cmd+Shift+P → Remote-SSH: Connect to Host → devbox
2. Open a repo folder on the remote host
3. If .devcontainer/ exists → "Reopen in Container"
   └── Docker pulls image on first open (~1 min, cached after)
   └── postCreateCommand runs (npm install, pip install, etc.)
   └── Extensions install inside the container
4. Code normally — terminal is inside the container
5. Ports in forwardPorts[] auto-forward to Mac localhost
```

### Containerizing a repo (`/containerize`)

Use the Claude Code skill from inside any repo to scaffold a `.devcontainer/`:

```
/containerize
```

Auto-detects stack (Node, Python, Go, Rust) and writes `.devcontainer/devcontainer.json` with the right base image, VS Code extensions, and `postCreateCommand`.

**Base images:**

| Stack | Image |
|---|---|
| Node 22 | `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm` |
| Python 3.12 | `mcr.microsoft.com/devcontainers/python:1-3.12-bookworm` |
| Go 1.22 | `mcr.microsoft.com/devcontainers/go:1-1.22-bookworm` |
| Rust | `mcr.microsoft.com/devcontainers/rust:1-bookworm` |
| Generic Debian | `mcr.microsoft.com/devcontainers/base:bookworm` |

### Rebuilding a container

If you change `devcontainer.json` or `Dockerfile`:

```
Cmd+Shift+P → Dev Containers: Rebuild Container
```

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `luis` | User to create |
| `ADMIN_USERNAME` | `$USERNAME` | Separate admin account; defaults to `USERNAME` for single-user dev boxes |
| `AGENT_USER` | `agent` | Dedicated agent system user (no sudo) |
| `TIMEZONE` | `America/Mexico_City` | Host timezone |
| `SKIP_FIREWALL` | `0` | Set to `1` to skip ufw + fail2ban. **sshd hardening still runs** (root login, password auth, etc. are disabled regardless). |
| `INSTALL_DOCKER` | `0` | Set to `1` to install rootful Docker alongside Podman (userns-remap enabled) |
| `GPU_PROFILE` | `consumer` | `consumer` (workstation/laptop GPUs) \| `datacenter` (enables `nvidia-persistenced` for Tesla/A100/H100) \| `none` (skip role 35 entirely). Role auto-skips anyway on hosts without an NVIDIA device. |
| `TS_AUTHKEY` | _(empty)_ | Tailscale auth key for unattended connect (cleared after use) |

> Legacy: `SKIP_UFW` is still honored as a fallback when `SKIP_FIREWALL` is unset.

---

## Testing

Bats-based E2E suite asserts post-bootstrap state: SSH posture, UFW rules,
fail2ban jail, user/sudoers separation, agent sandbox isolation, agent-run
escape rejection, container UID alignment, restic skeleton, log hygiene.

Install bats-core first — bootstrap does not install it (it's a test
dependency, not a runtime one):

```bash
# Ubuntu/Debian (the bootstrapped host)
sudo apt-get install -y bats

# macOS (only needed for run-local.sh on your Mac)
brew install bats-core
```

Then run the suite:

```bash
# On any bootstrapped host
sudo bats tests/e2e.bats

# Or spin up a throwaway Ubuntu 24.04 VM (requires multipass on your Mac)
tests/run-local.sh
```

CI runs `shellcheck` + `terraform validate` on every PR. The full E2E suite
is wired up but **manual-only** for now — fire it from the Actions UI or
`gh workflow run ci.yml` once a self-hosted runner is available.
