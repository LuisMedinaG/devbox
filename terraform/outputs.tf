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
  description = "Reconnect and monitoring commands. Cloud-init drives the bootstrap on first boot."
  value       = <<-EOT

    Bootstrap is running via cloud-init (~5–10 min).

    Tail progress:
      ssh root@${hcloud_server.devbox.ipv4_address} tail -f /var/log/cloud-init-output.log

    Wait for completion (blocks until done):
      ssh root@${hcloud_server.devbox.ipv4_address} cloud-init status --wait

    Set the user password (kept out of cloud-init for security):
      ssh root@${hcloud_server.devbox.ipv4_address} passwd ${var.username}

    Reconnect over Tailscale:
      tailscale ssh ${var.username}@${var.hostname}
  EOT
}
