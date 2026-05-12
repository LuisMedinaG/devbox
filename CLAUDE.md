# Claude Code Context — devbox

> Universal project context (repo layout, roles, constraints, editing guidelines) lives in `AGENTS.md`.
> This file contains only Claude Code-specific workflow and tooling.

## Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml`. Each requirement has a stable ACID (e.g. `bootstrap.HARDENING.1`).

- Write or update the spec before changing code.
- Reference ACIDs in code comments and test names — full ACID only, never partial.
- Never renumber requirements; use `deprecated: true` instead of deleting.
- Run `npx @acai.sh/cli skill` before planning implementation work to load the full acai workflow.

The `# bootstrap.ROLE.N` comment tags scattered throughout role scripts are ACID references — they trace each code block back to a requirement in `features/devbox/`. They are not arbitrary labels; do not remove or renumber them.

## Path-scoped rules

Loaded automatically based on the files being edited — no action needed:

| Rule | Globs |
|---|---|
| `.claude/rules/bootstrap-roles.md` | `bootstrap/roles/**`, `bootstrap/lib/**`, `bootstrap.sh` — idempotency helpers, dotfiles boundary, `download_verify` pattern |
| `.claude/rules/terraform.md` | `terraform/**` — Terraform owns the server resource only, no OS config |
| `.claude/rules/tests.md` | `tests/**` — ACID references required, tests run on host |

## NixOS Config Workflow

NixOS configuration lives in `nixos/`. The flake is the entry point:

```bash
# Validate flake syntax (run from repo root)
nix flake show

# Update all flake inputs to latest
nix flake update

# Deploy to a running NixOS devbox over SSH
nix run .#nixos-anywhere -- --flake .#devbox root@<ip>

# Rebuild on the devbox itself (after ssh'ing in)
sudo nixos-rebuild switch --flake /path/to/devbox#devbox
```

**Where things live:**

| Path | Purpose |
|---|---|
| `flake.nix` | Inputs (nixpkgs 25.05, home-manager, sops-nix, nixos-anywhere) |
| `nixos/hosts/devbox/default.nix` | Host entry point — imports all modules |
| `nixos/modules/<name>.nix` | One module per bootstrap role |
| `nixos/home/luis.nix` | home-manager config for the interactive user |
| `secrets/.sops.yaml` | sops age key registration; run `age-keygen` on first boot |

**Adding a new module:**
1. Create `nixos/modules/<name>.nix` — use `{ config, lib, pkgs, ... }: { }` as the base.
2. Add it to the `imports` list in `nixos/hosts/devbox/default.nix`.
3. Add ACID comment references matching `features/devbox/*.feature.yaml`.
4. Test: `sudo nixos-rebuild build` on a NixOS VM before deploying.

**Secrets workflow (sops-nix):**
1. Generate the host age key on first boot: `age-keygen -o /root/age/identity.txt`.
2. Copy the public key into `secrets/.sops.yaml` under `keys:`.
3. Create/edit secrets: `sops secrets/devbox/<name>.yaml`.
4. Reference in a module: `sops.secrets."<name>".owner = "...";`

## Slash commands

- `/update-docs` — audits `CLAUDE.md` and `AGENTS.md` against the current role scripts and proposes specific corrections. Run after any session where roles were added, removed, or meaningfully changed.
