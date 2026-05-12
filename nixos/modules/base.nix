{ config, lib, pkgs, ... }:
{
  # Phase 2: port bootstrap/roles/00-system.sh
  # Covers: bootstrap.SYSTEM.1-6
  # timezone, 2 GB swap, sysctl (swappiness/BBR/FQ), log rotation, MOTD suppression, unattended-upgrades
}
