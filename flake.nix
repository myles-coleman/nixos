{
  description = "NixOS configurations for my machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
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
      home-manager.nixosModules.default
      ./modules/home.nix
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

      homelab = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          home-manager.nixosModules.default
          ./hosts/homelab
        ];
      };

      bee-gpu-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          home-manager.nixosModules.default
          ./hosts/bee-gpu-server
        ];
      };

      protecli-vault = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          home-manager.nixosModules.default
          ./hosts/protecli-vault
        ];
      };

      pikvm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  system = "aarch64-linux";
                  config.allowUnfree = true;
                };
              })
            ];
          }
          ./hosts/pikvm
        ];
      };

      # Custom installer ISO for bee-gpu-server
      bee-gpu-server-installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          ./hosts/bee-gpu-server-installer/configuration.nix
        ];
      };
    };

    # ISO image output for easy building
    packages.x86_64-linux = {
      bee-gpu-server-iso = self.nixosConfigurations.bee-gpu-server-installer.config.system.build.isoImage;
    };
  };
}
