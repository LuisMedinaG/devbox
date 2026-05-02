#!/usr/bin/env bash
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

apt_install restic

HOME_DIR="/home/$USERNAME"

# The restic unit below backs up ~/projects; create it so the first timer
# fire doesn't fail with "no such file or directory".
install -d -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/projects"
install -d -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/.config/restic"
ENV_FILE="$HOME_DIR/.config/restic/env"
if [[ ! -f "$ENV_FILE" ]]; then
  cat >"$ENV_FILE" <<'EOF'
# Fill in and `chmod 600` this file before enabling the timer.
# export RESTIC_REPOSITORY="b2:bucket-name:devbox"
# export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"
# export B2_ACCOUNT_ID=""
# export B2_ACCOUNT_KEY=""
EOF
  chown "$USERNAME":"$USERNAME" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

install -d -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/.config/systemd/user"
cat >"$HOME_DIR/.config/systemd/user/restic-backup.service" <<'EOF'
[Unit]
Description=Restic backup

[Service]
Type=oneshot
EnvironmentFile=%h/.config/restic/env
ExecStart=/usr/bin/restic backup --exclude-caches \
  %h/projects %h/.config %h/.ssh
ExecStartPost=/usr/bin/restic forget --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6
EOF

cat >"$HOME_DIR/.config/systemd/user/restic-backup.timer" <<'EOF'
[Unit]
Description=Daily restic backup

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF

chown -R "$USERNAME":"$USERNAME" "$HOME_DIR/.config/systemd"
log "Backups: edit ~/.config/restic/env, then 'systemctl --user enable --now restic-backup.timer'"
