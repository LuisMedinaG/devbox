Audit CLAUDE.md and AGENT.md against the current state of the repo and propose specific, minimal updates.

## What to read

1. `bootstrap/bootstrap.sh` — authoritative role list and order
2. `bootstrap/roles/*.sh` — one file per role; filename = role name
3. `bootstrap/lib/common.sh` — helper function signatures
4. `bootstrap/config/versions.conf` — pinned tools
5. `CLAUDE.md` and `AGENT.md` — the docs to audit

Read all of the above before doing anything else.

## What to check

**Roles table** (appears in both docs)
- Every role in the `ROLES=()` array in `bootstrap.sh` must have a row.
- Each row's description must match what the role actually installs or configures.
- Roles removed from the array must be removed from the table.
- Order in the table must match execution order.

**common.sh helpers list**
- `CLAUDE.md` lists helpers in the "Repo layout" section. Verify it matches the actual function names in `common.sh`.

**Key constraints section** (AGENT.md)
- Bootstrap defaults (`USERNAME`, `TIMEZONE`, `SKIP_FIREWALL`) must match the `:=` defaults in `bootstrap.sh`.
- Any constraint that references a role number or behavior must still be accurate.

**Editing guidelines** (both docs)
- Any "new services" or "new firewall ports" guidance must name the correct role file.

**Anything else that is factually wrong** — stale role names, wrong file paths, removed features still documented.

## What NOT to change

- Writing style or prose — only fix facts.
- Sections that are still accurate — don't rewrite for the sake of it.
- Anything speculative or forward-looking.

## Output format

List each required change as:

**File:** `CLAUDE.md` or `AGENT.md`  
**Section:** exact heading  
**Change:** one sentence describing what is wrong  
**Fix:** the corrected text, ready to paste in (diff format or full replacement of the affected lines)

If nothing needs updating, say so explicitly. Do not propose cosmetic edits.
