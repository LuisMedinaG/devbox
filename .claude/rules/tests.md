---
globs: tests/**
---

- Tests run on the bootstrapped host as root — not on the Mac.
- Each test block must reference the full ACID(s) it covers (e.g. `# bootstrap.HARDENING.1`). Never partial IDs.
- New behavior added to a role → add a corresponding assertion in `e2e.bats`.
- Run locally via `tests/run-local.sh` (spins up a Multipass VM, bootstraps, runs bats, tears down).
