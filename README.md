# devbox

Personal cloud dev box running Claude Code on Hetzner. Persistent tmux sessions, survives disconnects. Access via Tailscale SSH or Mosh.

- **Machine**: CX23 (2 vCPU, 4 GB RAM, 40 GB SSD), location `nbg1`
- **OS**: Ubuntu 24.04
- **Access**: Tailscale SSH (primary), Mosh (mobile)

---

## Hetzner setup

### Prerequisites

```bash
brew install hcloud
hcloud context create devbox     # paste API token from console.hetzner.cloud
```

### Create server

```bash
# Upload your SSH key if not already in Hetzner
hcloud ssh-key create --name macbook --public-key-file ~/.ssh/id_ed25519.pub

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

```bash
hcloud server list
hcloud server reboot devbox
hcloud server poweroff devbox
hcloud server poweron devbox
hcloud server delete devbox      # permanent — back up first
```

---

## Bootstrap

Runs on a fresh host as root. Idempotent — safe to re-run.

### Before first run

Create `bootstrap/config/ssh-authorized-keys` (gitignored — never committed) from the template and paste in your pubkey(s):

```bash
cp bootstrap/config/ssh-authorized-keys.example bootstrap/config/ssh-authorized-keys
cat ~/.ssh/id_ed25519.pub >> bootstrap/config/ssh-authorized-keys
```

`bootstrap.sh` refuses to run without this file — role 20 disables password auth, so no keys = locked out.

### On the machine

```bash
# Install git (bare ubuntu image only)
apt-get update -y && apt-get install -y git

# Clone this repo
git clone https://github.com/LuisMedinaG/fly-devbox.git ~/projects/devbox
cd ~/projects/devbox/bootstrap

# Run full bootstrap
bash bootstrap.sh

# Or a subset
bash bootstrap.sh 10-user 40-dev-tools 50-shell 60-langs 70-claude-code

# With Tailscale auth key
TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh
```

### Roles

| # | Role | What it does |
|---|------|-------------|
| 00 | system | timezone, 2 GB swap, sysctl tweaks |
| 10 | user | create `luis`, passwordless sudo, SSH keys |
| 20 | hardening | harden sshd, ufw, fail2ban |
| 30 | tailscale | install + connect tailscale-ssh |
| 40 | dev-tools | git, tmux, zsh, ripgrep, fzf, btop, python3, mosh |
| 50 | shell | zsh default, starship prompt, tmux config |
| 60 | langs | Node (fnm), Python (uv), Rust, Go |
| 70 | claude-code | `npm install -g @anthropic-ai/claude-code` |
| 80 | docker | Docker CE + compose, `/srv/stacks` |
| 90 | backups | restic skeleton (activation is manual) |

### After bootstrap

```bash
su - luis
claude             # complete device-flow auth (opens URL, do this on your Mac)
tmux new -s work
```

---

## Access

### Tailscale setup (one-time)

1. Get an auth key at [tailscale.com/admin/settings/keys](https://tailscale.com/admin/settings/keys)
   - **Reusable**: yes — **Ephemeral**: no
2. Run the tailscale role with the key:
   ```bash
   TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh 30-tailscale
   ```
3. Verify from your Mac:
   ```bash
   tailscale status
   ssh <devbox-tailscale-name>
   ```

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

- Role 80 installs Docker CE and adds `luis` to the `docker` group.
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
| `TIMEZONE` | `America/Mexico_City` | Host timezone |
| `SKIP_FIREWALL` | `0` | Set to `1` to skip ufw + fail2ban. **sshd hardening still runs** (root login, password auth, etc. are disabled regardless). |
| `TS_AUTHKEY` | _(empty)_ | Tailscale auth key for unattended connect |

> Legacy: `SKIP_UFW` is still honored as a fallback when `SKIP_FIREWALL` is unset.
