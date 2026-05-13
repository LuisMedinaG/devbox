{ config, lib, pkgs, ... }:
{
  # Phase 2: port bootstrap/roles/20-hardening.sh
  # Covers: bootstrap.HARDENING.1-7
  # openssh module (no root login, no password auth, no X11), fail2ban
}
