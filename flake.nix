{
  description = "NixOS configurations for my machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    opencodeV2.url = "github:anomalyco/opencode/v2.0.23";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    sops-nix,
    nixos-raspberrypi,
    deploy-rs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({config, ...}: {
      systems = ["x86_64-linux" "aarch64-linux"];

      imports = [
        (inputs.import-tree ./modules/aspects)
        ./hosts/homelab
        ./hosts/bee-pc
        ./hosts/bee-gpd
        ./hosts/bee-gpu-server
        ./hosts/protecli-vault
        ./hosts/node0
        ./hosts/node1
        ./hosts/node2
        ./hosts/node3
        ./hosts/node4
        ./hosts/rpi3
      ];

      flake = let
        system = "x86_64-linux";
        mkUnstableOverlay = targetSystem: _final: _prev: {
          unstable = import nixpkgs-unstable {
            system = targetSystem;
            config.allowUnfree = true;
          };
        };
      in {
        nixosConfigurations = {
          bee-pc = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [config.flake.modules.nixos.bee-pc];
          };

          bee-gpd = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [config.flake.modules.nixos.bee-gpd];
          };

          homelab = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [config.flake.modules.nixos.homelab];
          };

          bee-gpu-server = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [config.flake.modules.nixos.bee-gpu-server];
          };

          protecli-vault = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [config.flake.modules.nixos.protecli-vault];
          };

          pikvm = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              {nixpkgs.overlays = [(mkUnstableOverlay "aarch64-linux")];}
              sops-nix.nixosModules.sops
              ./hosts/pikvm
            ];
          };

          node0 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.node0];
          };

          node1 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.node1];
          };

          node2 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.node2];
          };

          node3 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.node3];
          };

          node4 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.node4];
          };

          rpi3 = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = inputs;
            modules = [config.flake.modules.nixos.rpi3];
          };
        };

        deploy.nodes = {
          homelab = {
            hostname = "100.110.170.34";
            sshUser = "bee";
            profiles.system = {
              user = "root";
              magicRollback = true;
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.homelab;
            };
          };

          bee-gpu-server = {
            hostname = "100.127.170.8";
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
            hostname = "100.116.132.19";
            sshUser = "bee";
            profiles.system = {
              user = "root";
              magicRollback = true;
              activationTimeout = 600;
              confirmTimeout = 300;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pikvm;
            };
          };

          node0 = {
            hostname = "10.0.0.140";
            sshUser = "pi";
            profiles.system = {
              user = "root";
              magicRollback = true;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.node0;
            };
          };

          node1 = {
            hostname = "10.0.0.141";
            sshUser = "pi";
            profiles.system = {
              user = "root";
              magicRollback = true;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.node1;
            };
          };

          node2 = {
            hostname = "10.0.0.142";
            sshUser = "pi";
            profiles.system = {
              user = "root";
              magicRollback = true;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.node2;
            };
          };

          node3 = {
            hostname = "10.0.0.143";
            sshUser = "pi";
            profiles.system = {
              user = "root";
              magicRollback = true;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.node3;
            };
          };

          node4 = {
            hostname = "10.0.0.144";
            sshUser = "pi";
            profiles.system = {
              user = "root";
              magicRollback = true;
              activationTimeout = 600;
              confirmTimeout = 300;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.node4;
            };
          };

          rpi3 = {
            hostname = "10.0.0.145";
            sshUser = "bee";
            profiles.system = {
              user = "root";
              magicRollback = true;
              activationTimeout = 600;
              confirmTimeout = 300;
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi3;
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
            node0 = self.nixosConfigurations.node0.config.system.build.toplevel;
            node1 = self.nixosConfigurations.node1.config.system.build.toplevel;
            node2 = self.nixosConfigurations.node2.config.system.build.toplevel;
            node3 = self.nixosConfigurations.node3.config.system.build.toplevel;
            node4 = self.nixosConfigurations.node4.config.system.build.toplevel;
            rpi3 = self.nixosConfigurations.rpi3.config.system.build.toplevel;
          };
        };
      };
    });
}
