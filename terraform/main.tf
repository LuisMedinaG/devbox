# bootstrap.TERRAFORM.2
data "hcloud_ssh_key" "selected" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

locals {
  ts_tag    = coalesce(var.tailscale_tag, "tag:${var.hostname}")
  ts_script = "${path.module}/scripts/tailscale-device.sh"
}

# Pre-flight: remove any orphan Tailscale device with this hostname before the
# new server joins. Triggered on hostname change (and OAuth/tailnet config) —
# fires on first apply and whenever any trigger changes, ensuring a clean
# tailnet slot when re-provisioning under the same name.
resource "null_resource" "tailscale_preflight" {
  triggers = {
    hostname            = var.hostname
    oauth_client_id     = var.tailscale_oauth_client_id
    oauth_client_secret = var.tailscale_oauth_client_secret
    tailnet             = var.tailscale_tailnet
  }

  provisioner "local-exec" {
    command = "${local.ts_script} delete ${self.triggers.hostname}"
    environment = {
      TS_OAUTH_CLIENT_ID     = self.triggers.oauth_client_id
      TS_OAUTH_CLIENT_SECRET = self.triggers.oauth_client_secret
      TS_TAILNET             = self.triggers.tailnet
    }
  }
}

# bootstrap.TERRAFORM.1 bootstrap.TERRAFORM.3
resource "hcloud_server" "devbox" {
  depends_on  = [null_resource.tailscale_preflight]
  name        = var.hostname
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
  tags          = [local.ts_tag]
  expiry        = 3600
}

# Destroy-time cleanup — removes the device on `terraform destroy` so the next
# provision gets the clean hostname instead of "<hostname>-1", "<hostname>-2".
# Note: destroy provisioners can only reference `self.triggers`, so the script
# path is captured into triggers as well.
resource "null_resource" "tailscale_cleanup" {
  depends_on = [hcloud_server.devbox]

  triggers = {
    hostname            = var.hostname
    oauth_client_id     = var.tailscale_oauth_client_id
    oauth_client_secret = var.tailscale_oauth_client_secret
    tailnet             = var.tailscale_tailnet
    script              = local.ts_script
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${self.triggers.script} delete ${self.triggers.hostname}"
    environment = {
      TS_OAUTH_CLIENT_ID     = self.triggers.oauth_client_id
      TS_OAUTH_CLIENT_SECRET = self.triggers.oauth_client_secret
      TS_TAILNET             = self.triggers.tailnet
    }
  }
}
