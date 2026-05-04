data "hcloud_ssh_key" "selected" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

resource "hcloud_server" "devbox" {
  name        = var.server_name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [for k in data.hcloud_ssh_key.selected : k.id]
}
