# devbox

Personal cloud dev box running Claude Code on Hetzner. Persistent tmux
sessions, survives disconnects. Access via Tailscale SSH or Mosh.

- **Machine**: CX23 (2 vCPU, 4 GB RAM, 40 GB SSD), location `nbg1`
- **OS**: Ubuntu 24.04
- **Access**: Tailscale SSH (primary), Mosh (mobile)

---

## Quickstart

Provision and bootstrap from a clean Ubuntu 24.04 host. Pick your dotfiles auth
path (HTTPS is single-pass, SSH needs one re-run):

```bash
# 1. Provision (from your Mac)
export HCLOUD_TOKEN=<api-token>
cd terraform && terraform apply
ssh root@$(terraform output -raw ipv4)

# 2. On the host: clone this repo
apt-get update -y && apt-get install -y git
git clone https://github.com/LuisMedinaG/devbox.git ~/projects/devbox

# 3. Bootstrap
cd ~/projects/devbox/bootstrap

# Path A — single pass (recommended): pass a GitHub PAT for dotfiles HTTPS clone
TS_AUTHKEY=tskey-auth-xxxx \
  DOTFILES_TOKEN=ghp_xxxxxxxxxxxx \
  bash bootstrap.sh

# Path B — SSH dotfiles: bootstrap prints an SSH key, add it to GitHub, re-run
TS_AUTHKEY=tskey-auth-xxxx bash bootstrap.sh
# → follow on-screen NEXT STEPS (add key, then `bash bootstrap.sh 80-dotfiles`)
```

If you passed `USER_PASSWORD=`, the password is already set. Otherwise run
`passwd luis` before disconnecting. Reboot if a kernel update was applied.
Reconnect via `tailscale ssh luis@devbox`.

---

## Hetzner setup

Two ways to provision — pick one. Both end up with the same machine.

- **Terraform** (`terraform/`) — declarative, easy to recreate or vary.
- **`hcloud` CLI** — one-shot commands, no state file.

Get an API token first: <https://console.hetzner.com/projects/{project}/security/tokens>.

### Option A: Terraform

Prerequisite: at least one SSH public key uploaded to your Hetzner project.
Check with `hcloud ssh-key list`; upload one with
`hcloud ssh-key create --name <name> --public-key "$(cat ~/.ssh/id_ed25519.pub)"`.
The Terraform module references existing keys by name rather than uploading
them.

```bash
brew install terraform
export HCLOUD_TOKEN=your-token-here

cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit: list the SSH key names you want authorized, plus region/type overrides

terraform init
terraform apply
terraform output ipv4
```

Tear down: `terraform destroy`. State is in `terraform/terraform.tfstate`
(gitignored) — back it up or migrate to a remote backend if you care about
reproducibility.

> `cx`-line server types (Intel) are EU-only on some accounts. For
> `ash`/`hil`/`sin`, try `cpx21` (AMD) or `cax21` (ARM).

### Option B: hcloud CLI

```bash
brew install hcloud
hcloud context create devbox        # paste the API token

hcloud ssh-key create --name mac-pub-id_ed --public-key "$(cat ~/.ssh/id_ed25519.pub)"

hcloud server create \
  --name devbox \
  --type cx21 \
  --image ubuntu-24.04 \
  --location ash \
  --ssh-key mac-pub-id_ed

hcloud server list
```

### Lifecycle

```bash
hcloud server reboot   devbox
hcloud server poweroff devbox
hcloud server poweron  devbox
hcloud server delete   devbox      # permanent — back up first
```

> If you provisioned with Terraform, prefer `terraform destroy` so state stays
> in sync.

### Recreating the box

When you nuke and re-provision, two things in Tailscale don't auto-clean:

1. The old `devbox` node entry in your tailnet — remove it manually at
   <https://login.tailscale.com/admin/machines> if you want the hostname free
   immediately (otherwise it expires).
2. The previous auth key — generate a fresh one for the new box at
   <https://login.tailscale.com/admin/settings/keys>.

---

## Bootstrap roles

Idempotent, safe to re-run. Each role lives in `bootstrap/roles/`:

| #  | Role         | What it does |
|----|--------------|--------------|
| 00 | system       | timezone, 2 GB swap, sysctl, unattended-upgrade, log rotation |
| 10 | user         | create `luis`, narrow sudo, SSH `authorized_keys` |
| 20 | hardening    | sshd hardening, fail2ban (sshd jail) |
| 30 | tailscale    | install + connect tailscale-ssh; clears `TS_AUTHKEY` after use |
| 31 | firewall     | ufw + port 22 restricted to Tailscale CGNAT (after role 30) |
| 40 | dev-tools    | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm |
| 42 | docker       | rootless Podman (user is **not** in docker group) |
| 50 | shell        | zsh as default; `~/.zshrc.local` with machine PATH entries |
| 60 | langs        | Node, Python, Bun, Rust, Go via mise — single sha256-pinned binary |
| 70 | claude-code  | `npm install -g @anthropic-ai/claude-code` |
| 80 | dotfiles     | yadm clone + bootstrap, runs as the interactive user |

Logs at `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log`. Tail the latest:

```bash
tail -f /var/log/bootstrap/bootstrap-$(date +%Y%m%d)*.log
```

### SSH keys

Role 10 copies SSH keys to `~luis/.ssh/authorized_keys`, in priority order:

1. `bootstrap/config/ssh-authorized-keys` if present (gitignored)
2. `/root/.ssh/authorized_keys` — injected by Hetzner with `--ssh-key`

For non-Hetzner hosts:

```bash
cp bootstrap/config/ssh-authorized-keys.example bootstrap/config/ssh-authorized-keys
cat ~/.ssh/id_ed25519.pub >> bootstrap/config/ssh-authorized-keys
```

---

## Dotfiles

Role 80 deploys [LuisMedinaG/.dotfiles](https://github.com/LuisMedinaG/.dotfiles)
via yadm. Two clone paths — `DOTFILES_TOKEN` (HTTPS) is single-pass; SSH needs
one re-run.

### HTTPS (recommended)

Set `DOTFILES_TOKEN` to a GitHub PAT before running bootstrap. The token is
written to a temporary `~/.netrc` (mode 600) and removed via `trap` on exit;
it never touches argv, env (`ps`), git config, or logs.

Create a fine-grained PAT at <https://github.com/settings/tokens?type=beta>:
- **Repository access**: only `LuisMedinaG/.dotfiles`
- **Permissions → Contents**: Read-only
- **Expiration**: short (you only need it once)

```bash
DOTFILES_TOKEN=ghp_xxxxxxxxxxxx bash bootstrap.sh
```

### SSH (default)

Role 80 generates `~luis/.ssh/id_ed25519` and prints the public key. Add it to
GitHub at <https://github.com/settings/ssh/new>, then re-run:

```bash
sudo bash ~/projects/devbox/bootstrap/bootstrap.sh 80-dotfiles
```

Role 80 first runs an SSH connectivity pre-check (`BatchMode=yes`,
`ConnectTimeout=10`, `StrictHostKeyChecking=accept-new`) so failures surface
in seconds instead of hanging.

### Notes

- `~/.zshrc.local` (written by role 50, **not** tracked by yadm) holds
  `eval "$(mise activate zsh)"` and any other machine-specific entries. It
  survives `yadm clone` and is sourced by `.zshrc`.
- `yadm clone` runs with `--no-bootstrap`; bootstrap is invoked explicitly
  afterward to avoid double-runs in non-TTY contexts.

---

## Tailscale

Connect with `tailscale ssh luis@devbox` (no `~/.ssh/config` needed). Role 31
restricts public port 22 to the Tailscale CGNAT range
(`100.64.0.0/10`) — keys remain reachable only through the overlay.

### ACL (admin console → Access controls)

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

### Auth key settings

| Setting | Value |
|---|---|
| Reusable     | **no** (single-use per server) |
| Ephemeral    | **no** (devbox must persist after reboot) |
| Pre-approved | **yes** |
| Tags         | `tag:devbox` |

### Mobile (iOS)

Install **Tailscale** + a mosh-capable client (e.g. **Terminus**), point at the
devbox Tailscale IP, user `luis`, enable Mosh. Roams cleanly between Wi-Fi and
cellular.

---

## Claude Code

Installed by role 70. Use the built-in sandbox:

```bash
cd ~/path/to/repo
claude --sandbox
```

Or enable permanently in `.claude/settings.json`:

```json
{ "sandbox": { "enabled": true } }
```

---

## Environment variables

| Variable          | Default                | Description |
|-------------------|------------------------|-------------|
| `USERNAME`        | `luis`                 | User to create |
| `TIMEZONE`        | `America/Mexico_City`  | Host timezone |
| `SKIP_FIREWALL`   | `0`                    | `1` skips ufw + fail2ban; **sshd hardening still runs** |
| `TS_AUTHKEY`      | _(empty)_              | Tailscale auth key for unattended connect (cleared after use) |
| `DOTFILES_TOKEN`  | _(empty)_              | GitHub PAT for HTTPS dotfiles clone (no SSH key needed) |
| `USER_PASSWORD`   | _(empty)_              | If set, role 10 runs `chpasswd` — eliminates manual `passwd` step |

---

## More

- [`tests/README.md`](tests/README.md) — bats E2E suite, local VM runner
- [`docs/dev-containers.md`](docs/dev-containers.md) — VS Code Remote-SSH +
  Dev Containers workflow
- [`features/README.md`](features/README.md) — spec-driven development with
  acai.sh
