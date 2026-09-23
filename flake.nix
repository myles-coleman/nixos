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
  };
}
