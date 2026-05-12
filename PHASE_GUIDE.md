# Phase Guide: NixOS Migration

This file is a living prompt for Phase 1 and Phase 2 work. Reference GitHub issues for detailed tasks and constraints.

---

## Phase 1: Scaffold NixOS Config Structure

**GitHub Issue:** #38 (nixos-migration, phase-1)

**Duration:** 2–3 days

**Branch:** `phase-1` (created from `dev`)

### Objectives

1. Create `nixos/` directory structure
2. Write `flake.nix` with all inputs locked
3. Create empty module stubs for all 12 roles
4. Create entry points: `hosts/devbox/default.nix` and `home/luis.nix`
5. Create `secrets/` directory with `.sops.yaml` template
6. Create `nixos-migration.feature.yaml` with Phase 1–4 ACIDs
7. Update `terraform/cloud-init.yaml.tpl` to call `nixos-anywhere`
8. Verify flake syntax
9. Update documentation files

### Exit Criteria

- [ ] `git diff dev` shows all new files (nixos/, secrets/, feature files)
- [ ] `nix flake show` runs without errors
- [ ] `flake.lock` is generated and committed
- [ ] All 12 module stubs exist (empty, but present)
- [ ] CLAUDE.md and AGENTS.md reference nixos-migration
- [ ] Feature files split with all old ACIDs preserved
- [ ] PR to `dev` branch created
- [ ] Code review approved
- [ ] Merged to `dev`

### Documentation Updates Required

Before merging, ensure:
- [ ] **CLAUDE.md**: Add section "NixOS Config Workflow" — how to rebuild, where flakes live, how to add modules
- [ ] **AGENTS.md**: Update "Repository Layout" section — document `nixos/` structure, explain module pattern
- [ ] **README.md**: Update "Provisioning" section — mention nixos-anywhere, NixOS-specific workflow
- [ ] **features/devbox/**: Document ACID naming scheme for NixOS modules

### Useful Commands

```bash
# Check flake syntax
nix flake show

# List inputs
nix flake metadata

# Format Nix files (optional, keeps code clean)
nix fmt
```

---

## Phase 2: Port Bash Roles to NixOS Modules

**GitHub Issue:** #39 (nixos-migration, phase-2)

**Duration:** 3–5 days

**Branch:** `phase-2` (created from `dev`)

### Objectives

Port all 12 bootstrap roles to NixOS modules, in order of complexity (simple first):

1. `base.nix` (SYSTEM.1–6) — sysctl, swap, timezone, timesyncd
2. `users.nix` (USER.1–4) — user creation, SSH keys, sudo
3. `firewall.nix` (FIREWALL.1–3) — nftables rules
4. `hardening.nix` (HARDENING.1–7) — openssh module, fail2ban
5. `tailscale.nix` (TAILSCALE.1–5) — services.tailscale + sops secret
6. `dev-tools.nix` (DEV_TOOLS.1) — environment.systemPackages
7. `podman.nix` (DOCKER.1–7) — virtualisation.podman module
8. `caddy.nix` (CADDY.1–5) — services.caddy + virtualHosts
9. `shell.nix` + `home/luis.nix` (SHELL.1–4) — zsh, history, prompt
10. `claude-code.nix` (CLAUDE_CODE.1–2) — activation script for npm install
11. `dotfiles.nix` (DOTFILES.1–5) — yadm clone in activation
12. `ollama.nix` (OLLAMA.1–4) — services.ollama module

### Implementation Pattern

For each module:
1. Read the corresponding bash role (e.g., `bootstrap/roles/00-system.sh`)
2. Identify exact behavior: packages, files, services, system calls
3. Write NixOS equivalent using modules (don't reinvent)
4. Add ACID comment references (`# bootstrap.SYSTEM.1`, etc.)
5. Test incrementally on local NixOS VM: `sudo nixos-rebuild build`
6. Commit per module with message: `feat(nixos): implement MODULENAME (ACID refs)`

### Exit Criteria

- [ ] All 12 modules implemented and tested locally
- [ ] All ACID references preserved in comments
- [ ] No custom bash in modules (use NixOS modules and packages)
- [ ] `sudo nixos-rebuild switch` works without errors on test VM
- [ ] PR to `dev` branch created
- [ ] Code review approved
- [ ] Merged to `dev`

### Documentation Updates Required

Before merging, ensure:
- [ ] **CLAUDE.md**: Add module-specific examples (e.g., "To add a new systemd service, see `modules/caddy.nix`")
- [ ] **AGENTS.md**: Document the module pattern and how to extend it
- [ ] **nixos-migration.feature.yaml**: Update with Phase 2 completion ACIDs
- [ ] **README.md**: Add "Configuration" section explaining NixOS module structure

### Useful Commands

```bash
# Check module syntax
nix eval -f '<nixpkgs/nixos>' config.system.build.toplevel 2>&1 | head -20

# Build without switching (test first)
sudo nixos-rebuild build -I nixos-config=/path/to/configuration.nix

# Show what would change
sudo nixos-rebuild switch --dry-run

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# List available modules
nix search nixpkgs services.
```

---

## Transition: Phase 1 → Phase 2

When Phase 1 PR is merged to `dev`:

```bash
git checkout dev
git pull origin dev
git checkout -b phase-2
```

Start Phase 2 work.

---

## Transition: Phase 2 → Phase 3

When Phase 2 PR is merged to `dev`:

```bash
git checkout dev
git pull origin dev
git checkout -b phase-3
```

Start Phase 3 (cloud deployment).

---

## Cross-Phase Checklist

**At the end of EVERY phase:**

- [ ] All ACID references are in code comments (preserved from original)
- [ ] CLAUDE.md reflects current tooling and workflow
- [ ] AGENTS.md repo layout section is current
- [ ] README.md provisioning section is current
- [ ] Feature files are split and up-to-date
- [ ] No uncommitted changes
- [ ] PR opened to `dev` with clear description
- [ ] Code review completed
- [ ] Merged to `dev`

**GitHub Issue Context:**

Always reference the issue number in commit messages:

```bash
git commit -m "feat: description (see #38 Phase 1)"
```

This auto-links commits to GitHub issues for traceability.

---

## Getting Help

If stuck:
1. Check GitHub issue (#38 or #39) for detailed tasks
2. Read corresponding bash role for exact behavior
3. Search NixOS manual: https://nixos.org/manual/nixos/stable/
4. Check nixpkgs for existing modules: https://github.com/NixOS/nixpkgs/tree/master/nixos/modules
5. Ask claude-mem: "How did we handle X in the bash version?"

---

## Next: After Phase 2

Once Phase 2 is merged to `dev`, the architecture is complete and tested locally. Phase 3 will provision a live Hetzner VM and validate on real infrastructure.
