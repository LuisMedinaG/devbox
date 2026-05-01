# fly-devbox

Personal cloud dev box running Claude Code on Fly.io. Persistent tmux sessions,
survives disconnects. Same bootstrap targets Hetzner for a traditional VPS setup.

- **Machine**: `performance-2x` (2 vCPU, 4 GB RAM), region `dfw`
- **Storage**: 40 GB persistent volume mounted at `/home`
- **Access**: Tailscale SSH (primary) — `fly ssh console` is the fallback
- **No public ports**

---

## Fly.io setup

### Prerequisites

```bash
fly auth login
fly orgs list          # confirm your org slug (used below as "personal")
```

### One-time infrastructure

```bash
# Create the app (only once — do not re-run)
fly apps create lumedina-devbox --org personal

# Create the persistent volume (only once)
fly volumes create devbox_data \
  --app lumedina-devbox \
  --region dfw \
  --size 40
```

### Deploy

```bash
# Build image and deploy machine
fly deploy

# Check machine state
fly status
fly machine list

# View logs
fly logs
fly logs --instance <machine-id>
```

### SSH access

```bash
# Connect as root
fly ssh console

# Connect directly as the dev user
fly ssh console --user luis
```

### Machine lifecycle

```bash
# Start a stopped machine
fly machine start <machine-id>

# Stop without destroying (saves compute cost)
fly machine stop <machine-id>

# Hard restart
fly machine restart <machine-id>

# Destroy machine (volume is NOT deleted)
fly machine destroy <machine-id>

# Recreate from current image after destroy
fly deploy
```

### Volume management

```bash
fly volumes list
fly volumes show <volume-id>

# Extend volume size (cannot shrink)
fly volumes extend <volume-id> --size 80
```

---

## Hetzner setup

### Prerequisites

```bash
# Install hcloud CLI
brew install hcloud

# Authenticate
hcloud context create devbox     # paste API token from console.hetzner.cloud
```

### Create server

```bash
# Upload your SSH key first if not already in Hetzner
hcloud ssh-key create --name macbook --public-key-file ~/.ssh/id_ed25519.pub

# Create server — CX23: 2 vCPU, 4 GB RAM, 40 GB SSD
hcloud server create \
  --name devbox \
  --type cx23 \
  --image ubuntu-24.04 \
  --location nbg1 \
  --ssh-key macbook

# Get the IP
hcloud server list
```

### Server lifecycle

```bash
hcloud server list
hcloud server status devbox
hcloud server reboot devbox
hcloud server poweroff devbox
hcloud server poweron devbox
hcloud server delete devbox      # permanent — back up first
```

---

## Bootstrap

Runs on a fresh host as root. Idempotent — safe to re-run.

### Before first run

Add your SSH public key to `bootstrap/config/ssh-authorized-keys` (one key per line).
Without this, `10-user` will warn and skip key installation.

```bash
cat ~/.ssh/id_ed25519.pub >> bootstrap/config/ssh-authorized-keys
```

### On the machine

```bash
# Install git (bare ubuntu image only)
apt-get update -y && apt-get install -y git

# Clone this repo
git clone https://github.com/LuisMedinaG/fly-devbox.git /opt/devbox
cd /opt/devbox/bootstrap

# Run full bootstrap (defaults: USERNAME=luis, SKIP_UFW=1)
bash bootstrap.sh

# Or a subset
bash bootstrap.sh 10-user 40-dev-tools 50-shell 60-langs 70-claude-code

# Hetzner: enable ufw + fail2ban
SKIP_UFW=0 bash bootstrap.sh

# With Tailscale auth
TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh
```

### Roles

| # | Role | What it does |
|---|------|-------------|
| 00 | system | timezone, swap (`/home/swapfile`), sysctl |
| 10 | user | create `luis`, passwordless sudo, SSH keys |
| 20 | hardening | harden sshd; ufw + fail2ban (skipped when `SKIP_UFW=1`) |
| 30 | tailscale | install + connect tailscale-ssh |
| 40 | dev-tools | git, sudo, tmux, zsh, ripgrep, fzf, btop, python3 |
| 50 | shell | zsh default, starship prompt, tmux config |
| 60 | langs | Node (fnm), Python (uv), Rust, Go |
| 70 | claude-code | `npm install -g @anthropic-ai/claude-code` |
| 80 | docker | Docker CE + compose, `/srv/stacks` |
| 90 | backups | restic skeleton (activation is manual) |

### After bootstrap

```bash
su - luis          # or: fly ssh console --user luis
claude             # complete device-flow auth (opens URL, do this on your Mac)
tmux new -s work
```

---

## Access

### Tailscale setup (one-time per host)

1. Get an auth key at [tailscale.com/admin/settings/keys](https://tailscale.com/admin/settings/keys)
   - **Reusable**: yes — **Ephemeral**: no — **Expiry**: 90 days or none
2. On the machine, run the tailscale role:
   ```bash
   TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh 30-tailscale
   ```
3. Rename the machine in [tailscale.com/admin/machines](https://tailscale.com/admin/machines)
   - Fly machine registers as the Fly machine ID — rename to `lumedina-devbox`
   - Hetzner machine registers as its hostname — rename to `devbox-hetzner`
4. Verify from your Mac:
   ```bash
   tailscale status
   ssh devbox-flyio
   ssh devbox-hetzner
   ```

### Mac `~/.ssh/config`

```
Host devbox-flyio
  HostName lumedina-devbox
  User luis

Host devbox-hetzner
  HostName devbox-hetzner
  User luis
  IdentityFile ~/.ssh/id_ed25519
```

> Use the Tailscale IP (`100.x.x.x`) instead of the hostname until MagicDNS resolves it.

### iOS — Tailscale + Terminus

1. Install **Tailscale** from the App Store — sign in with the same account
2. Set a password for the `luis` user on the machine (Terminus uses password auth):
   ```bash
   passwd luis
   ```
3. In **Terminus**: add a new host
   - **Host**: `100.64.54.128` (Fly) or the Tailscale IP of the Hetzner box
   - **User**: `luis`
   - **Auth**: password

The connection goes over Tailscale WireGuard — the password is never exposed to the internet.

### Fallback (no Tailscale)

```bash
fly ssh console             # Fly only — requires flyctl installed
fly ssh console --user luis
```

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `luis` | User to create |
| `TIMEZONE` | `America/Mexico_City` | Host timezone |
| `SKIP_UFW` | `1` | Skip ufw/fail2ban (set to `0` on Hetzner) |
| `TS_AUTHKEY` | _(empty)_ | Tailscale auth key for unattended connect |
