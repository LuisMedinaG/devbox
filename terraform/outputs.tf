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
  description = "Run these commands after apply to provision the server (wait ~30s for sshd)."
  value       = <<-EOT

    ssh root@${hcloud_server.devbox.ipv4_address}
    apt-get install -y git
    git clone ${var.devbox_repo} ~/projects/devbox
    cd ~/projects/devbox
    USERNAME=luis TS_AUTHKEY=<key> DOTFILES_TOKEN=<pat> bash bootstrap/bootstrap.sh
  EOT
}
