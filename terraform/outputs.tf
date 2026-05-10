# bootstrap.TERRAFORM.4
output "ipv4" {
  description = "Public IPv4 of the devbox."
  value       = hcloud_server.devbox.ipv4_address
}

output "ipv6" {
  description = "Public IPv6 of the devbox."
  value       = hcloud_server.devbox.ipv6_address
}

output "status" {
  description = "Server power/lifecycle status."
  value       = hcloud_server.devbox.status
}

output "next_steps" {
  description = "Ready-to-run bootstrap commands (printed after apply). Contains the (1-hour) Tailscale auth key."
  sensitive   = true
  value       = <<-EOT

    ssh root@${hcloud_server.devbox.ipv4_address}
    apt-get update -y && apt-get install -y git
    git clone ${var.devbox_repo} ~/projects/devbox
    cd ~/projects/devbox
    USERNAME=luis \
      MACHINE_NAME=${var.hostname} \
      TS_TAG=${local.ts_tag} \
      TS_AUTHKEY=${tailscale_tailnet_key.devbox.key} \
      DOTFILES_REPO=https://github.com/LuisMedinaG/.dotfiles.git \
      bash bootstrap/bootstrap.sh
  EOT
}
