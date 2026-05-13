# devbox

Personal cloud dev box running Claude Code on Hetzner. Persistent tmux
sessions, survives disconnects. Access via Tailscale SSH or Mosh.

- **Machine**: CX23 (2 vCPU, 4 GB RAM, 40 GB SSD), location `nbg1`
- **OS**: NixOS 25.05 (migrating from Ubuntu 24.04 — see `nixos/`)
- **Access**: Tailscale SSH (primary), Mosh (mobile)

---

## Quickstart

One command provisions, bootstraps, and joins the box to your tailnet:

```bash
export HCLOUD_TOKEN=<hetzner-api-token>
cd terraform && terraform apply
```

Cloud-init runs on first boot: generates the host age key for secrets, then
invokes `nixos-anywhere` to install NixOS from the flake. No manual SSH step.

Watch progress (~5–10 min):

```bash
ssh root@$(terraform output -raw ipv4) tail -f /var/log/cloud-init-output.log
# or block until done:
ssh root@$(terraform output -raw ipv4) cloud-init status --wait
```

Run `terraform output next_steps` for the same commands templated with the
correct IP and username.

### NixOS provisioning details

The NixOS flake lives at `flake.nix`. The host configuration is in
`nixos/hosts/devbox/default.nix`, which imports all 12 modules under
`nixos/modules/`. Secrets (Tailscale auth key, etc.) are encrypted with
`sops-nix` using an age key generated on first boot.

**Re-deploy config changes to a running box:**

```bash
# From your Mac (uses nixos-anywhere under the hood)
nix run .#nixos-anywhere -- --flake .#devbox root@<tailscale-ip>

# Or on the box itself
sudo nixos-rebuild switch --flake /path/to/devbox#devbox
```

**Manage secrets:**

```bash
# Edit a secret (encrypts on save)
sops secrets/devbox/tailscale-authkey.yaml

# After rotating the host age key: re-encrypt all secrets
sops updatekeys secrets/devbox/*.yaml
```

### After bootstrap finishes

```bash
# Set the user password (kept out of cloud-init for security — see below):
ssh root@<ip> passwd luis

# Reconnect via Tailscale:
tailscale ssh luis@devbox
```

Tear down with `terraform destroy` — the Tailscale device is removed
automatically so the next provision gets the clean hostname back. A pre-flight
cleanup also runs on every `terraform apply` that creates or replaces the
server.

### What's in `user_data`

Cloud-init runs as root on first boot with these env vars injected from
Terraform: `USERNAME`, `MACHINE_NAME`, `TS_TAG`, `TS_AUTHKEY`, `DOTFILES_REPO`.

| Var | Sensitivity | Reason it's safe to embed |
|-----|-------------|---------------------------|
| `TS_AUTHKEY` | secret, **short-lived** | 1-hour expiry, single-device-join scope; useless once consumed |
| Others | non-secret | hostname / repo URL / username |

`USER_PASSWORD` is intentionally **excluded**. Hetzner stores `user_data` for
the lifetime of the server (readable via the API), so a long-lived password
there would leak indefinitely. Set it manually post-bootstrap.

### Debugging a stuck or failed bootstrap

Cloud-init creates three debug surfaces on the box:

| Path | Purpose |
|---|---|
| `/var/log/bootstrap/STATE` | One-line health: `running` → `ok` or `failed:<rc>` |
| `/etc/devbox-bootstrap.env` (root-only) | Exact env vars cloud-init injected — re-sourceable |
| `/usr/local/bin/devbox-rerun [role...]` | Re-runs bootstrap with the same env; pulls latest first |

#### Quick health check

```bash
# Is bootstrap still running, or did it finish?
ssh root@<ip> cat /var/log/bootstrap/STATE

# Is cloud-init itself still running?
ssh root@<ip> cloud-init status

# What env was injected?
ssh root@<ip> cat /etc/devbox-bootstrap.env
```

#### Log files

| Log | When to check |
|---|---|
| `/var/log/cloud-init-output.log` | First boot — cloud-init orchestration, git clone, initial bootstrap run |
| `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log` | Any bootstrap run — full role-by-role output with timestamps |
| `/var/log/bootstrap/STATE` | Quick health without parsing logs |

```bash
# Tail the latest bootstrap log
ssh root@<ip> 'tail -f /var/log/bootstrap/bootstrap-$(date +%Y%m%d)*.log'

# Search for errors in the latest log
ssh root@<ip> 'grep -i "fail\|error" /var/log/bootstrap/bootstrap-$(date +%Y%m%d)*.log | tail -20'
```

#### Common failure scenarios

| Symptom | Likely cause | Fix |
|---|---|---|
| `STATE` stuck on `running` for >15 min | Cloud-init still running, or hung on a role | `ssh root@<ip> cloud-init status` — if `done`, check bootstrap log; if `running`, wait or `ssh root@<ip> ps aux \| grep bootstrap` |
| `STATE` = `failed:<rc>` | A role exited non-zero | Check bootstrap log for the failing role; fix and `devbox-rerun` |
| `tailscale up` fails | Auth key expired (1 h) or network issue | Generate a new key in Tailscale admin; `ssh root@<ip> devbox-rerun 30-tailscale` |
| Role 80 (dotfiles) fails | SSH key not added to GitHub, or repo is private | Add the printed pubkey to GitHub; re-run `devbox-rerun 80-dotfiles` |
| Role 60 (langs) fails | Network timeout downloading mise | Retry with `devbox-rerun 60-langs` — downloads are cached on success |
| Can't SSH after bootstrap | Tailscale not connected, or UFW blocked port 22 | Connect via Hetzner console; `ssh root@<ip> devbox-rerun 30-tailscale 31-firewall` |
| `devbox-rerun` fails git pull | Local tree has uncommitted changes | `ssh root@<ip> 'cd /root/projects/devbox && git stash && devbox-rerun'` |

#### Recovery workflow

```bash
# Re-run full bootstrap (role cache skips completed roles)
ssh root@<ip> devbox-rerun

# Re-run just one role after fixing it
ssh root@<ip> devbox-rerun 80-dotfiles

# Force a clean re-run of a specific role (bypasses cache)
ssh root@<ip> 'rm /var/lib/bootstrap/cache/80-dotfiles.sha256 && devbox-rerun 80-dotfiles'

# Edit injected env and re-run (e.g. change DOTFILES_REPO)
ssh root@<ip> 'vim /etc/devbox-bootstrap.env && devbox-rerun'

# Run a role that wasn't in the original profile
ssh root@<ip> 'source /etc/devbox-bootstrap.env && cd /root/projects/devbox && bash bootstrap/bootstrap.sh svc-ollama'
```

#### When to destroy and recreate

If bootstrap fails on role 00 (system) or role 10 (user), it's usually faster to `terraform destroy && terraform apply` than to debug. These roles run first — if they fail, the box is in a partially-configured state. For failures in roles 30+, `devbox-rerun` is almost always the right path.

---

## Hetzner setup

Two ways to spin up a server — pick one. They are NOT equivalent:

- **Terraform** (`terraform/`) — declarative, full provision + bootstrap + Tailscale join in a single `terraform apply`. Recommended.
- **`hcloud` CLI** — creates a bare server only. You then SSH in and run `bootstrap.sh` manually with `TS_AUTHKEY=...` etc. Useful for one-off experiments.

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

When you re-provision via Terraform, both Tailscale concerns are handled
automatically:

- The old device with the same hostname is removed by `null_resource.tailscale_preflight` before the new server joins (and again by `null_resource.tailscale_cleanup` on `terraform destroy`).
- A fresh 1-hour auth key is generated per `terraform apply`.

If you provisioned via the `hcloud` CLI (no Terraform state), you'll still need
to remove the old node manually at <https://login.tailscale.com/admin/machines>.

---

## Bootstrap roles

Idempotent, safe to re-run. Each role lives in `bootstrap/roles/`:

| #  | Role         | What it does |
|----|--------------|--------------|
| 00 | system       | timezone, 2 GB swap, sysctl, unattended-upgrade, log rotation |
| 10 | user         | create `$USERNAME`, narrow sudo, SSH `authorized_keys` |
| 20 | hardening    | sshd hardening, fail2ban (sshd jail) |
| 30 | tailscale    | install + connect tailscale-ssh; clears `TS_AUTHKEY` after use |
| 31 | firewall     | ufw + port 22 restricted to Tailscale CGNAT (after role 30) |
| 40 | dev-tools    | git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm, pipx |
| 42 | docker       | rootless Podman + `podman-compose` + `docker-compose` shim (user is **not** in docker group) |
| 43 | caddy        | Caddy reverse proxy — auto-HTTPS, `/health` endpoint, `conf.d/` for service snippets |
| 50 | shell        | zsh as default; `~/.zshrc.local` with machine PATH entries |
| 60 | langs        | Node, Python, Bun, Rust, Go via mise — single sha256-pinned binary |
| 70 | claude-code  | `npm install -g @anthropic-ai/claude-code` + claude-mem MCP server |
| 80 | dotfiles     | yadm clone + bootstrap, runs as the interactive user |

Logs at `/var/log/bootstrap/bootstrap-YYYYMMDD-HHMMSS.log`. Tail the latest:

```bash
tail -f /var/log/bootstrap/bootstrap-$(date +%Y%m%d)*.log
```

### SSH keys

Role 10 copies SSH keys to `~$USERNAME/.ssh/authorized_keys`, in priority order:

1. `bootstrap/config/ssh-authorized-keys` if present (gitignored)
2. `/root/.ssh/authorized_keys` — injected by Hetzner with `--ssh-key`

For non-Hetzner hosts:

```bash
cp bootstrap/config/ssh-authorized-keys.example bootstrap/config/ssh-authorized-keys
cat ~/.ssh/id_ed25519.pub >> bootstrap/config/ssh-authorized-keys
```

---

## Dotfiles

Role 80 deploys your dotfiles via yadm. Set `DOTFILES_REPO` to your repo URL
(SSH or HTTPS). If unset, the role is skipped with a warning.

Role 80 tries a plain HTTPS clone first — no credentials needed for public
repos. If that fails (private repo), it falls back to SSH.

### HTTPS (default, public repos)

Pass an HTTPS URL and the clone requires no token:

```bash
DOTFILES_REPO=https://github.com/<owner>/.dotfiles.git bash bootstrap.sh
```

### SSH (private repos or push access)

Role 80 generates `~$USERNAME/.ssh/id_ed25519` and prints the public key. Add it to
GitHub at <https://github.com/settings/ssh/new>, then re-run:

```bash
sudo bash ~/projects/devbox/bootstrap.sh 80-dotfiles
```

Role 80 first runs an SSH connectivity pre-check (`BatchMode=yes`,
`ConnectTimeout=10`, `StrictHostKeyChecking=accept-new`) so failures surface
in seconds instead of hanging.

### GitHub PAT (reference — for cloning other private repos on the host)

If you need to clone private repos from the host after provisioning, store a
fine-grained PAT in `~/.netrc` (mode 600):

```
machine github.com login x-access-token password ghp_xxxxxxxxxxxx
```

Create a PAT at <https://github.com/settings/tokens?type=beta>:
- **Repository access**: only the repos you need
- **Permissions → Contents**: Read-only

### Notes

- `~/.zshrc.local` (written by role 50, **not** tracked by yadm) holds
  `eval "$(mise activate zsh)"` and any other machine-specific entries. It
  survives `yadm clone` and is sourced by `.zshrc`.
- `yadm clone` runs with `--no-bootstrap`; bootstrap is invoked explicitly
  afterward to avoid double-runs in non-TTY contexts.

---

## Tailscale

Connect with `tailscale ssh $USERNAME@devbox` (no `~/.ssh/config` needed). Role 31
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

Terraform generates a fresh auth key per `terraform apply` with these
properties (see `terraform/main.tf` `tailscale_tailnet_key.devbox`). If you
mint one manually in the admin console, mirror them:

| Setting | Value |
|---|---|
| Reusable     | **no** (single-use per server) |
| Ephemeral    | **no** (devbox must persist after reboot) |
| Pre-approved | **yes** |
| Expiry       | **1 hour** (only needed during the initial `tailscale up`) |
| Tags         | `tag:${hostname}` (default `tag:devbox`) |

### Mobile (iOS)

Install **Tailscale** + a mosh-capable client (e.g. **Terminus**), point at the
devbox Tailscale IP, user `$USERNAME`, enable Mosh. Roams cleanly between Wi-Fi and
cellular.

---

## Claude Code

Installed by role 70 alongside the [claude-mem](https://github.com/thedotmack/claude-mem) MCP server.

### claude-mem install — non-interactive contract

Role 70 redirects stdin from `/dev/null` so the installer runs silently
under both cloud-init and a human SSH session. claude-mem picks its
own recommended defaults when stdin is not a TTY:

| Setting | Default |
|---|---|
| IDE | `claude-code` |
| Runtime | `worker` |
| Provider | `claude` |
| Auth method | `subscription` (uses the logged-in `claude` CLI account) |
| Model | `claude-haiku-4-5-20251001` (cheap/fast for compression) |
| Worker auto-start | skipped during install; role starts it explicitly afterwards |

**First-login caveat**: subscription auth requires the `claude` CLI on
the host to be logged in. On a fresh devbox the worker installs and
starts, but claude-mem can't compress anything until you log into
Claude Code once:

```bash
tailscale ssh luis@devbox
claude   # complete the OAuth flow on first launch
```

**Overrides** (don't remove the stdin redirect — pass flags instead):

```bash
# In role 70, replace the install line with whichever override you need:
as_user 'mise exec node -- npx --yes claude-mem install \
  --ide claude-code \
  --provider claude \
  --model claude-sonnet-4-6 \
  --no-auto-start </dev/null'

# Or for API-key auth instead of subscription:
as_user 'CLAUDE_MEM_CLAUDE_AUTH_METHOD=api-key \
         ANTHROPIC_API_KEY=sk-ant-... \
         mise exec node -- npx --yes claude-mem install --no-auto-start </dev/null'
```

### Sandbox

Use the built-in sandbox:

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
| `USERNAME`        | _(required)_           | User to create — explicit or auto-detected from `$SUDO_USER` |
| `MACHINE_NAME`    | `devbox`               | Tailscale device hostname + advertised tag prefix |
| `TS_TAG`          | `tag:${MACHINE_NAME}`  | Tailscale ACL tag for the device |
| `TS_AUTHKEY`      | _(empty)_              | Tailscale auth key for unattended connect (cleared after use) |
| `DOTFILES_REPO`   | _(empty — skip)_       | yadm dotfiles repo URL; role 80 is skipped if unset |
| `TIMEZONE`        | `America/Mexico_City`  | Host timezone |
| `SKIP_FIREWALL`   | `0`                    | `1` skips UFW activation; fail2ban + sshd hardening still run |
| `SKIP_SSH_HARDENING` | `0`                 | `1` skips role 20's sshd drop-in; fail2ban still runs |
| `DEV_MODE`        | `0`                    | `1` = umbrella escape hatch: sets `SKIP_FIREWALL=1` and `SKIP_SSH_HARDENING=1`. **Dev only.** |
| `USER_PASSWORD`   | _(empty)_              | If set, role 10 runs `chpasswd` — eliminates manual `passwd` step |

---

## More

- [`tests/README.md`](tests/README.md) — bats E2E suite, local VM runner
- [`docs/dev-containers.md`](docs/dev-containers.md) — VS Code Remote-SSH +
  Dev Containers workflow
- [`features/README.md`](features/README.md) — spec-driven development with
  acai.sh
