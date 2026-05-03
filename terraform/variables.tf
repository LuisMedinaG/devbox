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

variable "ssh_key_name" {
  description = "Name to register the SSH public key under in Hetzner."
  type        = string
  default     = "macbook"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to upload and authorize for root."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
