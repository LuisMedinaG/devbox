{ config, lib, pkgs, ... }:
{
  # Phase 2: port bootstrap/roles/31-firewall.sh
  # Covers: bootstrap.FIREWALL.1-3
  # networking.firewall (nftables), open SSH + Mosh, restrict port 22 to Tailscale CGNAT
}
