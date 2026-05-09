# Claude Code Context — devbox

> Universal project context (repo layout, roles, constraints, editing guidelines) lives in `AGENTS.md`.
> This file contains only Claude Code-specific workflow and tooling.

## Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml`. Each requirement has a stable ACID (e.g. `bootstrap.HARDENING.1`).

- Write or update the spec before changing code.
- Reference ACIDs in code comments and test names — full ACID only, never partial.
- Never renumber requirements; use `deprecated: true` instead of deleting.
- Run `npx @acai.sh/cli skill` before planning implementation work to load the full acai workflow.

## Path-scoped rules

Loaded automatically based on the files being edited — no action needed:

| Rule | Globs |
|---|---|
| `.claude/rules/bootstrap-roles.md` | `bootstrap/roles/**`, `bootstrap/lib/**`, `bootstrap.sh` — idempotency helpers, dotfiles boundary, `download_verify` pattern |
| `.claude/rules/terraform.md` | `terraform/**` — Terraform owns the server resource only, no OS config |
| `.claude/rules/tests.md` | `tests/**` — ACID references required, tests run on host |

## Slash commands

- `/update-docs` — audits `CLAUDE.md` and `AGENTS.md` against the current role scripts and proposes specific corrections. Run after any session where roles were added, removed, or meaningfully changed.
