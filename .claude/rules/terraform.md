---
globs: terraform/**
---

Terraform owns the Hetzner server resource only — no OS-level configuration here.
Shell config, packages, users, and services belong in `bootstrap/roles/`.

SSH keys are referenced by name (`data "hcloud_ssh_key"`), never uploaded or stored in this repo.
