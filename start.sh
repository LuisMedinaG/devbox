#!/bin/sh
# Fly machine entrypoint — starts installed services, keeps the machine alive.
# Runs on every machine boot as the CMD (via tini).
# Services are started only if their binary exists (safe before bootstrap runs).

[ -x /usr/sbin/sshd ]       && /usr/sbin/sshd
[ -x /usr/sbin/dockerd ]    && dockerd >/var/log/dockerd.log 2>&1 &
[ -x /usr/sbin/tailscaled ] && tailscaled >/var/log/tailscaled.log 2>&1 &

exec sleep infinity
