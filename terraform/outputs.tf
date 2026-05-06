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
