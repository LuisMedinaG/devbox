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
  description = "Reconnect, monitoring, and debug commands. Cloud-init drives bootstrap on first boot."
  value       = <<-EOT

    Bootstrap is running via cloud-init (~5–10 min).

    ── Monitor ─────────────────────────────────────────────────────────────
    Tail progress:
      ssh root@${hcloud_server.devbox.ipv4_address} tail -f /var/log/cloud-init-output.log

    Check overall status (exit 0 = success):
      ssh root@${hcloud_server.devbox.ipv4_address} cat /var/log/bootstrap/STATE

    Wait for completion (blocks until done, returns cloud-init status):
      ssh root@${hcloud_server.devbox.ipv4_address} cloud-init status --wait

    ── Debug / re-run ──────────────────────────────────────────────────────
    Inspect the env vars cloud-init injected:
      ssh root@${hcloud_server.devbox.ipv4_address} cat /etc/devbox-bootstrap.env

    Re-run full bootstrap with the original env (idempotent; role cache skips done roles):
      ssh root@${hcloud_server.devbox.ipv4_address} devbox-rerun

    Re-run a single role:
      ssh root@${hcloud_server.devbox.ipv4_address} devbox-rerun 80-dotfiles

    ── Post-bootstrap ──────────────────────────────────────────────────────
    Set the user password (kept out of cloud-init for security):
      ssh root@${hcloud_server.devbox.ipv4_address} passwd ${var.username}

    Reconnect over Tailscale:
      tailscale ssh ${var.username}@${var.hostname}
  EOT
}
