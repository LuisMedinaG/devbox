{ config, lib, pkgs, ... }:
{
  # Phase 2: port shell/dotfiles user-level config to home-manager
  # Mirrors bootstrap.SHELL.1-4 and bootstrap.DOTFILES.1-5 for the 'luis' user.
  home.username = "luis";
  home.homeDirectory = "/home/luis";
  home.stateVersion = "25.05";
}
