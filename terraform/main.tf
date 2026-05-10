# bootstrap.TERRAFORM.2
data "hcloud_ssh_key" "selected" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

# bootstrap.TERRAFORM.1 bootstrap.TERRAFORM.3
resource "hcloud_server" "devbox" {
  name        = var.server_name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [for k in data.hcloud_ssh_key.selected : k.id]
}

# One-time auth key for bootstrap — non-reusable, non-ephemeral, preauthorized.
# Expires in 1 hour (only needed during the initial `tailscale up`).
resource "tailscale_tailnet_key" "devbox" {
  reusable      = false
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:devbox"]
  expiry        = 3600
}

# Remove the Tailscale device on `terraform destroy` so the next provision gets
# the clean hostname "devbox" instead of "devbox-1", "devbox-2", etc.
resource "null_resource" "tailscale_cleanup" {
  depends_on = [hcloud_server.devbox]

  triggers = {
    oauth_client_id     = var.tailscale_oauth_client_id
    oauth_client_secret = var.tailscale_oauth_client_secret
    tailnet             = var.tailscale_tailnet
    hostname            = var.server_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-SH
      token=$(curl -sf -X POST \
        -d "client_id=${self.triggers.oauth_client_id}&client_secret=${self.triggers.oauth_client_secret}" \
        https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
      device_id=$(curl -sf \
        -H "Authorization: Bearer $token" \
        "https://api.tailscale.com/api/v2/tailnet/${self.triggers.tailnet}/devices" \
        | jq -r --arg h "${self.triggers.hostname}" \
            '.devices[] | select(.hostname == $h) | .id' | head -1)
      if [ -n "$device_id" ]; then
        curl -sf -X DELETE \
          -H "Authorization: Bearer $token" \
          "https://api.tailscale.com/api/v2/device/$device_id"
        echo "Removed Tailscale device: ${self.triggers.hostname} ($device_id)"
      else
        echo "No Tailscale device named '${self.triggers.hostname}' found — nothing to remove."
      fi
    SH
  }
}
