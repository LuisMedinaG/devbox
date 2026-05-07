# VS Code SSH Remote + Dev Containers

Connect VS Code on your Mac to the devbox and open repos in isolated Podman
containers — same experience as GitHub Codespaces, self-hosted.

## Mac prerequisites

1. **Remote - SSH** extension in VS Code
2. **Dev Containers** extension in VS Code
3. Tailscale running and signed into the same account

## Host prerequisites (handled by bootstrap)

- Rootless Podman (role 42) is the default container runtime. Its socket is
  exposed as `DOCKER_HOST` in `~/.zshenv.local` so Dev Containers works without
  installing Docker.
- VS Code CLI — install once on the host:

  ```bash
  curl -fL 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
    | tar -xz -C ~/.local/bin
  ```

## Workflow

1. VS Code on Mac → `Cmd+Shift+P` → **Remote-SSH: Connect to Host** → `devbox`
2. Open a repo folder on the remote host
3. If `.devcontainer/` exists → **Reopen in Container**
   - Image pulls on first open (~1 min, cached after)
   - `postCreateCommand` runs (`npm install`, `pip install`, …)
   - Extensions install inside the container
4. Code normally — terminal is inside the container
5. Ports in `forwardPorts[]` auto-forward to Mac localhost

## Containerizing a repo (`/containerize`)

Use the Claude Code skill from inside any repo to scaffold a `.devcontainer/`:

```
/containerize
```

Auto-detects stack (Node, Python, Go, Rust) and writes
`.devcontainer/devcontainer.json` with the right base image, VS Code
extensions, and `postCreateCommand`.

| Stack | Image |
|---|---|
| Node 22 | `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm` |
| Python 3.12 | `mcr.microsoft.com/devcontainers/python:1-3.12-bookworm` |
| Go 1.22 | `mcr.microsoft.com/devcontainers/go:1-1.22-bookworm` |
| Rust | `mcr.microsoft.com/devcontainers/rust:1-bookworm` |
| Generic Debian | `mcr.microsoft.com/devcontainers/base:bookworm` |

## Rebuilding a container

After changes to `devcontainer.json` or `Dockerfile`:

```
Cmd+Shift+P → Dev Containers: Rebuild Container
```
