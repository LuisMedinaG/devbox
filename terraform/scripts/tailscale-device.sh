#!/usr/bin/env bash
# Delete a Tailscale device by hostname. Idempotent — exits 0 if no match.
# Used by both pre-flight (create-time) and cleanup (destroy-time) null_resources.
#
# Usage: tailscale-device.sh delete <hostname>
# Env:   TS_OAUTH_CLIENT_ID, TS_OAUTH_CLIENT_SECRET, TS_TAILNET
set -euo pipefail

cmd="${1:-}"; hostname="${2:-}"
[[ "$cmd" = "delete" && -n "$hostname" ]] || {
  echo "usage: $0 delete <hostname>" >&2
  exit 2
}

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool is required but not installed" >&2; exit 1; }
done
: "${TS_OAUTH_CLIENT_ID:?TS_OAUTH_CLIENT_ID is required}"
: "${TS_OAUTH_CLIENT_SECRET:?TS_OAUTH_CLIENT_SECRET is required}"
: "${TS_TAILNET:?TS_TAILNET is required}"

token=$(curl -sf -X POST \
  -d "client_id=${TS_OAUTH_CLIENT_ID}&client_secret=${TS_OAUTH_CLIENT_SECRET}" \
  https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
[[ -n "$token" && "$token" != "null" ]] || { echo "OAuth token exchange failed" >&2; exit 1; }

device_id=$(curl -sf -H "Authorization: Bearer $token" \
  "https://api.tailscale.com/api/v2/tailnet/${TS_TAILNET}/devices" \
  | jq -r --arg h "$hostname" '.devices[] | select(.hostname == $h) | .id' | head -1)

if [[ -n "$device_id" ]]; then
  curl -sf -X DELETE -H "Authorization: Bearer $token" \
    "https://api.tailscale.com/api/v2/device/$device_id"
  echo "Removed Tailscale device: $hostname ($device_id)"
else
  echo "No Tailscale device named '$hostname' — nothing to do."
fi
