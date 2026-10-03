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
    # Declarative disk partitioning for the k3s NVMe nodes (program Phase 4).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    sops-nix,
    nixos-raspberrypi,
    deploy-rs,
    ...
  }: let
    system = "x86_64-linux";
    # System-parameterized so the same overlay shape can serve x86_64 and
    # aarch64 hosts without a second nixpkgs instantiation.
    mkUnstableOverlay = targetSystem: _final: _prev: {
      unstable = import nixpkgs-unstable {
        system = targetSystem;
        config.allowUnfree = true;
      };
    };
    unstableOverlay = mkUnstableOverlay system;
    commonModules = [
      {nixpkgs.overlays = [unstableOverlay];}
      ./modules/roles
      ./modules/common.nix
      ./modules/desktop.nix
      ./modules/networking.nix
      ./modules/dev-tools.nix
      ./modules/gaming.nix
      sops-nix.nixosModules.sops
      home-manager.nixosModules.default
      ./modules/home.nix
    ];
    # Shared module set for the imported k3s cluster nodes (program Phase 4).
    rpiK3sModules = [
      ./modules/sops.nix
      sops-nix.nixosModules.sops
      ./modules/rpi/base.nix
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
          ./modules/roles
          home-manager.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/homelab
        ];
      };

      bee-gpu-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          ./modules/roles
          home-manager.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/bee-gpu-server
          ./modules/steam-remote-play-client.nix
        ];
      };

      protecli-vault = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {nixpkgs.overlays = [unstableOverlay];}
          ./modules/roles
          home-manager.nixosModules.default
          ./hosts/protecli-vault
          sops-nix.nixosModules.sops
        ];
      };

      pikvm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          {nixpkgs.overlays = [(mkUnstableOverlay "aarch64-linux")];}
          sops-nix.nixosModules.sops
          ./hosts/pikvm
        ];
      };

      # k3s cluster (program Phase 4). Imported from rpi5-nixos; node0 is the
      # control plane, node1-node4 are agents, and node4 boots from an SD card.
      node0 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = rpiK3sModules ++ [./hosts/node0];
      };

      node1 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = rpiK3sModules ++ [./hosts/node1];
      };

      node2 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = rpiK3sModules ++ [./hosts/node2];
      };

      node3 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = rpiK3sModules ++ [./hosts/node3];
      };

      node4 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = rpiK3sModules ++ [./hosts/node4];
      };

      # rpi3 Chromium kiosk (program Phase 4). Migrated from rpi3-nixos onto
      # the vendor `raspberry-pi-3` board and SD-image modules.
      rpi3 = nixos-raspberrypi.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs;
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/rpi3
        ];
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

      # k3s cluster + rpi3 (program Phase 4). Manual (`workflow_dispatch`) only:
      # they are deliberately kept out of the merge auto-deploy set. Deploy
      # reaches them over the LAN via protecli-vault's advertised subnet routes.
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

      # SD-card boot: allow a longer activation/confirmation window.
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

      # rpi3's only user is `bee` (preserved from its source config); sshUser is
      # `bee` rather than the k3s nodes' `pi`. SD-card boot.
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
        node0 = self.nixosConfigurations.node0.config.system.build.toplevel;
        node1 = self.nixosConfigurations.node1.config.system.build.toplevel;
        node2 = self.nixosConfigurations.node2.config.system.build.toplevel;
        node3 = self.nixosConfigurations.node3.config.system.build.toplevel;
        node4 = self.nixosConfigurations.node4.config.system.build.toplevel;
        rpi3 = self.nixosConfigurations.rpi3.config.system.build.toplevel;
      };
    };
  };
}
