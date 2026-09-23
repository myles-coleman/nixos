# Temporary: PR lane exercise (Spec 08 T3.9) — safe to discard.
{
  description = "NixOS configurations for my machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs/e760371d631165e7d8de5b0dcf148e21ec4c16f0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    sops-nix,
    deploy-rs,
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
          ./modules/steam-remote-play-client.nix
        ];
      };

      protecli-vault = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          home-manager.nixosModules.default
          ./hosts/protecli-vault
          sops-nix.nixosModules.sops
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
    };

    deploy.nodes = {
      homelab = {
        hostname = "10.0.0.150";
        sshUser = "bee";
        profiles.system = {
          user = "root";
          magicRollback = true;
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.homelab;
        };
      };

      bee-gpu-server = {
        hostname = "10.0.0.156";
        sshUser = "bee";
        profiles.system = {
          user = "root";
          magicRollback = true;
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.bee-gpu-server;
        };
      };

      protecli-vault = {
        hostname = "100.112.185.27";
        sshUser = "bee";
        profiles.system = {
          user = "root";
          magicRollback = true;
          activationTimeout = 600;
          confirmTimeout = 300;
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.protecli-vault;
        };
      };

      pikvm = {
        hostname = "10.0.0.175";
        sshUser = "bee";
        profiles.system = {
          user = "root";
          magicRollback = true;
          activationTimeout = 600;
          confirmTimeout = 300;
          path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pikvm;
        };
      };
    };

    checks = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"] (
      checkSystem: deploy-rs.lib.${checkSystem}.deployChecks self.deploy
    );

    apps = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"] (
      appSystem: {
        deploy = deploy-rs.apps.${appSystem}.deploy-rs;
      }
    );

    # Host toplevels for CI build lanes (`nix-fast-build --flake .#packages.<system>`).
    packages = {
      x86_64-linux = {
        bee-pc = self.nixosConfigurations.bee-pc.config.system.build.toplevel;
        bee-gpd = self.nixosConfigurations.bee-gpd.config.system.build.toplevel;
        homelab = self.nixosConfigurations.homelab.config.system.build.toplevel;
        bee-gpu-server = self.nixosConfigurations.bee-gpu-server.config.system.build.toplevel;
        protecli-vault = self.nixosConfigurations.protecli-vault.config.system.build.toplevel;
      };
      aarch64-linux = {
        pikvm = self.nixosConfigurations.pikvm.config.system.build.toplevel;
      };
    };
  };
}
