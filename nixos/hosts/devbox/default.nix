{ config, lib, pkgs, ... }:
{
  imports = [
    ../../modules/base.nix
    ../../modules/users.nix
    ../../modules/hardening.nix
    ../../modules/tailscale.nix
    ../../modules/firewall.nix
    ../../modules/dev-tools.nix
    ../../modules/podman.nix
    ../../modules/caddy.nix
    ../../modules/shell.nix
    ../../modules/claude-code.nix
    ../../modules/dotfiles.nix
    # svc-ollama is opt-in; enable with: imports = [ ../../modules/ollama.nix ];
  ];

  networking.hostName = "devbox";

  home-manager.users.luis = import ../../home/luis.nix;

  # Populated during Phase 2
  system.stateVersion = "25.05";
}
