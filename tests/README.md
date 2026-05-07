# Tests

Bats-based E2E suite that asserts post-bootstrap state: SSH posture, UFW rules,
fail2ban jail, user/sudoers separation, Podman rootless, log hygiene.

## Run on a bootstrapped host

```bash
sudo apt-get install -y bats        # role 40 already installs this
sudo bats tests/e2e.bats
```

## Run locally in a throwaway VM

Requires `multipass` on macOS:

```bash
brew install bats-core
tests/run-local.sh
```

The script spins up a fresh Ubuntu 24.04 VM, runs the full bootstrap, then runs
the bats suite inside it. Tears the VM down on exit.

## CI

`shellcheck` + `terraform validate` + `acai push` run on every PR via
`.github/workflows/ci.yml`.
