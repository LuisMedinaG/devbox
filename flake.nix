{
  description = "devbox — NixOS configuration for a personal cloud dev box on Hetzner";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, nixos-anywhere, ... }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.devbox = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./nixos/hosts/devbox
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
        ];
      };

      # Make nixos-anywhere available as a deploy app (run from Mac with:
      #   nix run .#nixos-anywhere -- --flake .#devbox root@<ip>)
      apps.${system}.nixos-anywhere = nixos-anywhere.apps.${system}.nixos-anywhere;
    };
}
