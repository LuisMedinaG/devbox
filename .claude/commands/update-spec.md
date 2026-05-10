Audit `features/devbox/bootstrap.feature.yaml` against the current state of the repo and propose specific, minimal updates.

## What to read

1. `bootstrap/bootstrap.sh` — authoritative role list, role cache logic, env var defaults
2. `bootstrap/roles/*.sh` — one file per role; the `# bootstrap.<COMPONENT>.<N>` comments are ACID anchors
3. `bootstrap/lib/common.sh` — helper functions referenced by the spec
4. `bootstrap/config/versions.conf` — pinned tools (informs LANGS, DEV_TOOLS)
5. `terraform/*.tf` and `terraform/cloud-init.yaml.tpl` — informs TERRAFORM component
6. `features/devbox/bootstrap.feature.yaml` — the spec to audit

Read all of the above before drafting changes.

## What to check

**Component coverage** — every role file in `bootstrap/roles/` must map to a spec component. New roles → new component. Removed roles → mark requirements `deprecated: true` (do not delete).

**Requirement accuracy** — for every requirement, verify the corresponding role still implements it. ACID comments in the role (`# bootstrap.FOO.3`) must point at a real requirement in the spec.

**Numbering rules (hard)**
- Never renumber existing requirements. Numbers are stable identifiers referenced from code comments and tests.
- Removed behavior → mark `deprecated: true`, never delete.
- New behavior → append the next free integer (or sub-requirement like `7-1`).
- If you find code referencing an ACID that doesn't exist in the spec, ADD the missing requirement — do not change the code's reference.

**TERRAFORM component** — covers everything under `terraform/`:
- `hcloud_server` resource and its inputs (name, type, image, location, ssh_keys, user_data).
- `tailscale_tailnet_key` and the OAuth-backed `null_resource` blocks (pre-flight + destroy-time cleanup).
- `cloud-init.yaml.tpl` — what env vars it injects and what it intentionally excludes.
- The `var.hostname` single-variable convention (Hetzner name + Tailscale hostname + tag derivation).

**ENG constraints**
- Idempotency, role cache (Docker-style), log path, role-arg execution model, dotfiles boundary.
- Bootstrap env var defaults (`USERNAME`, `TIMEZONE`, `MACHINE_NAME`, `TS_TAG`, `SKIP_FIREWALL`) must match the `:=` defaults in `bootstrap.sh`.

**Cross-cutting**
- Anything embedding secrets or making security trade-offs (TS_AUTHKEY in user_data, USER_PASSWORD intentionally manual) deserves an explicit requirement so future changes can't silently regress it.

## What NOT to change

- Wording style or prose ordering of sections that are still accurate.
- Existing requirement numbers — never renumber.
- Anything speculative or forward-looking (e.g. roles you might add later).

## Output format

For each change, output:

**Section:** `components.<COMPONENT>` or `constraints.<NAME>`
**Change type:** `add requirement` | `mark deprecated` | `correct description` | `add component`
**Why:** one sentence pointing at the file/lines that prove the spec is wrong
**YAML to insert/update:** the exact lines, ready to paste in (preserve indentation)

If nothing needs updating, say so explicitly. Do not propose cosmetic edits.

After the user approves, apply the edits with the Edit tool — preserve YAML formatting (2-space indent, no trailing whitespace) and do not reorder existing keys.
