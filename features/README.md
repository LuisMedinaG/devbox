# Spec-driven development (acai.sh)

Feature specs live in `features/devbox/` as `*.feature.yaml` files. Each
requirement has a stable ID (ACID) referenced in code comments and test names
for traceability — e.g. `# bootstrap.HARDENING.1`.

## Dashboard

Specs and ACID coverage sync to the [acai.sh dashboard](https://app.acai.sh)
on every CI run. Review acceptance coverage per feature there.

## Local push

```bash
echo "ACAI_API_TOKEN=at_your_token" > .env   # gitignored
npx @acai.sh/cli push --all
```

## Rotate the GitHub Actions secret

```bash
gh secret set ACAI_API_TOKEN --body "$ACAI_API_TOKEN" --repo LuisMedinaG/devbox
gh secret list --repo LuisMedinaG/devbox
```

## Add a new spec

1. Create `features/devbox/<feature-name>.feature.yaml`
2. Reference ACIDs in code/tests as comments — `# bootstrap.HARDENING.1`
3. Push: `npx @acai.sh/cli push --all` (or let CI do it)
