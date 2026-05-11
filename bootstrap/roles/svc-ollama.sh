#!/usr/bin/env bash
# Installs Ollama (local LLM server). Opt-in — not in the default role sequence.
# Run standalone: sudo ./bootstrap.sh svc-ollama  (USERNAME auto-detected from $SUDO_USER)
# Access via Tailscale: http://<tailscale-ip>:11434 (not exposed to public internet)
# bootstrap.OLLAMA.1 bootstrap.OLLAMA.2 bootstrap.OLLAMA.3 bootstrap.OLLAMA.4
set -euo pipefail
source "$SCRIPT_DIR/lib/common.sh"

source_versions
detect_arch OLLAMA

OLLAMA_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${ARCH_FULL}.tar.zst"

# bootstrap.OLLAMA.1 — install binary from verified archive
if ! command -v ollama >/dev/null 2>&1; then
  log "Installing Ollama ${OLLAMA_VERSION} ..."
  apt_install zstd
  download_verify "$OLLAMA_URL" /tmp/ollama.tar.zst "$OLLAMA_SHA256"
  tar -I zstd -xf /tmp/ollama.tar.zst -C /usr/local
  rm -f /tmp/ollama.tar.zst
fi

# bootstrap.OLLAMA.2 — dedicated service account + model storage
if ! id ollama >/dev/null 2>&1; then
  useradd -r -s /bin/false -d /usr/local/lib/ollama \
    -c "Ollama service account" ollama
fi
mkdir -p /var/lib/ollama/models
chown -R ollama:ollama /var/lib/ollama

# bootstrap.OLLAMA.3 — systemd service
if [[ ! -f /etc/systemd/system/ollama.service ]]; then
  cat > /etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"

[Install]
WantedBy=default.target
EOF
  systemctl daemon-reload
fi

# bootstrap.OLLAMA.4 — Caddy snippet (commented out; activate by adding a domain)
CADDY_SNIPPET="/etc/caddy/conf.d/ollama.conf"
if [[ ! -f "$CADDY_SNIPPET" ]]; then
  cat > "$CADDY_SNIPPET" <<'EOF'
# Ollama HTTPS proxy — uncomment and set your domain to activate.
# After editing, run: systemctl reload caddy
#
# ollama.example.com {
#     reverse_proxy localhost:11434
# }
EOF
fi

enable_service ollama
