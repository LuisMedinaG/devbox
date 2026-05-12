{ config, lib, pkgs, ... }:
{
  # Phase 2: port bootstrap/roles/30-tailscale.sh
  # Covers: bootstrap.TAILSCALE.1-5
  # services.tailscale, sops secret for TS_AUTHKEY, hostname + advertise-tags
}
