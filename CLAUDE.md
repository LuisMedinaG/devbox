# Claude Code Context — devbox

> Universal project context (repo layout, roles, constraints, editing guidelines) lives in `AGENTS.md`.
> This file contains only Claude Code-specific workflow and tooling.

## Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml`. Each requirement has a stable ACID (e.g. `bootstrap.HARDENING.1`).

- Write or update the spec before changing code.
- Reference ACIDs in code comments and test names — full ACID only, never partial.
- Never renumber requirements; use `deprecated: true` instead of deleting.
- Run `npx @acai.sh/cli skill` before planning implementation work to load the full acai workflow.

## Slash commands

- `/update-docs` — audits `CLAUDE.md` and `AGENTS.md` against the current role scripts and proposes specific corrections. Run after any session where roles were added, removed, or meaningfully changed.
