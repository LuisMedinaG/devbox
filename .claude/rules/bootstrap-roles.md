---
globs: bootstrap/roles/**,bootstrap/lib/**,bootstrap/bootstrap.sh
---

## Idempotency — required in every role

All roles must be safe to re-run. Use the helpers from `bootstrap/lib/common.sh`:

| Helper | Use for |
|---|---|
| `ensure_line <line> <file>` | Append a line only if absent |
| `source_versions` | Load pinned versions from config/versions.conf (idempotent) |
| `detect_arch [TOOL]` | Detect CPU arch; with prefix, validates & exports arch-specific SHA256 |
| `apt_install <pkg...>` | Install packages (DEBIAN_FRONTEND=noninteractive) |
| `apt_update_once` | Run `apt-get update` at most once per hour |
| `download_verify <url> <dest> <sha256>` | Download + verify — no curl\|sh |
| `as_user '<cmd>'` | Run a command as `$USERNAME` via login shell |
| `enable_service <name>` | `systemctl enable --now` |

Never use raw `echo >>` or `apt-get install` directly — always go through the helpers.

If a helper fails, log the error and exit with a non-zero status. For example, if `download_verify` fails, the role should report the failure and exit `1` so the bootstrap process stops cleanly.

## Adding a new third-party binary

1. Add `TOOL_VERSION`, `TOOL_SHA256_AMD64`, `TOOL_SHA256_ARM64` to `bootstrap/config/versions.conf`.
2. Use `download_verify` in the role — never pipe from curl.
3. Guard the install with a `command -v` or path check so re-runs skip it.

## Dotfiles boundary

Bootstrap must never write to files dotfiles owns: `.zshrc`, `.zshenv`, `.gitconfig`.
Machine-specific shell entries go in `~/.zshrc.local` or `~/.zshenv.local`.

## Profiles

Named role sets in `bootstrap.sh` (`PROFILES` map). Default: `devbox`.
Set `PROFILE=<name>` to select a lightweight set. Explicit role args bypass profiles.
To add a profile, add an entry to the `PROFILES` map — reference existing roles only.
