{
  description = "NixOS configurations for my machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    ...
  }: let
    system = "x86_64-linux";
    unstableOverlay = final: prev: {
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    };
    commonModules = [
      {nixpkgs.overlays = [unstableOverlay];}
      ./modules/common.nix
      ./modules/desktop.nix
      ./modules/networking.nix
      ./modules/dev-tools.nix
      ./modules/gaming.nix
    ];
  in {
    nixosConfigurations = {
      bee-pc = nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          commonModules
          ++ [
            ./hosts/bee-pc
          ];
      };

      bee-gpd = nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          commonModules
          ++ [
            ./hosts/bee-gpd
            ./modules/nvidia.nix
          ];
      };
    };
  };
}
