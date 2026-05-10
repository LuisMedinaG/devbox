variable "hcloud_token" {
  description = <<-EOT
    Hetzner Cloud API token. Create one at https://console.hetzner.com/projects/<project-id>/security/tokens.
    Leave unset to fall back to the HCLOUD_TOKEN environment variable (preferred — avoids
    storing the token on disk).
  EOT
  type        = string
  sensitive   = true
  default     = null
}

variable "server_name" {
  description = "Hetzner server name."
  type        = string
  default     = "devbox"
}

variable "server_type" {
  description = "Hetzner server type. cx23 = 2 vCPU, 4 GB RAM, 40 GB SSD."
  type        = string
  default     = "cx23"
}

variable "location" {
  description = <<-EOT
    Hetzner datacenter location.
      EU:       nbg1 (Nuremberg), fsn1 (Falkenstein), hel1 (Helsinki)
      US:       ash (Ashburn, VA), hil (Hillsboro, OR)
      APAC:     sin (Singapore)
    Note: the `cx` (Intel) server-type line is EU-only on some accounts; US/APAC may require `cpx` (AMD) or `cax` (ARM).
    Verify with: `hcloud server-type describe <type> -o json | jq '.prices[].location' | sort -u`
  EOT
  type        = string
  default     = "nbg1"
}

variable "image" {
  description = "Base OS image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "devbox_repo" {
  description = "Git URL of this repo, cloned on the server during bootstrap."
  type        = string
  default     = "https://github.com/LuisMedinaG/devbox.git"
}

variable "tailscale_oauth_client_id" {
  description = <<-EOT
    Tailscale OAuth client ID. Create one at https://login.tailscale.com/admin/settings/oauth
    with scopes: auth_keys (write), devices (read + delete).
    Used to generate a one-time auth key and to remove the device on destroy.
  EOT
  type      = string
  sensitive = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret (paired with tailscale_oauth_client_id)."
  type      = string
  sensitive = true
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name — shown in the admin console (e.g. 'example.com' or the org slug)."
  type        = string
}

variable "ssh_key_names" {
  description = <<-EOT
    Names of SSH public keys already uploaded to your Hetzner project.
    All listed keys are authorized for root on the new server.
    List existing keys with: `hcloud ssh-key list`.
    Upload a new one with: `hcloud ssh-key create --name <name> --public-key "$(cat ~/.ssh/id_ed25519.pub)"`.
  EOT
  type        = list(string)

  validation {
    condition = length(var.ssh_key_names) > 0 && alltrue([
      for name in var.ssh_key_names : trimspace(name) == name && trimspace(name) != ""
    ])
    error_message = "ssh_key_names must contain at least one entry, and every entry must be non-empty with no surrounding whitespace (the Hetzner API matches names exactly)."
  }
}
