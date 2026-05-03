variable "hcloud_token" {
  description = "Hetzner Cloud API token. Create one at https://console.hetzner.com/projects/<project-id>/security/tokens"
  type        = string
  sensitive   = true
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
  description = "Hetzner datacenter location (e.g. nbg1, fsn1, hel1, ash, hil)."
  type        = string
  default     = "nbg1"
}

variable "image" {
  description = "Base OS image."
  type        = string
  default     = "ubuntu-24.04"
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
      for name in var.ssh_key_names : trimspace(name) != ""
    ])
    error_message = "ssh_key_names must contain at least one non-empty key name; otherwise Hetzner emails a root password instead of authorizing key-based SSH."
  }
}
