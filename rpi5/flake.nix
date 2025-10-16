{
  description = "NixOS configuration for Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = {
    self,
    nixpkgs,
    nixos-raspberrypi,
    disko,
  } @ inputs: let
    system = "x86_64-linux";
    targetSystem = "aarch64-linux";
  in {
    nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystem {
      system = targetSystem;
      specialArgs = inputs;
      modules = [
        nixos-raspberrypi.nixosModules.raspberry-pi-5.base
        nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
        nixos-raspberrypi.nixosModules.raspberry-pi-5.bluetooth
        nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
        disko.nixosModules.disko
        ./disko-config.nix

        ({pkgs, ...}: {
          networking = {
            hostName = "node1";
          };

          users.users.pi = {
            initialPassword = "raspberry";
            isNormalUser = true;
            extraGroups = ["wheel"];
          };

          services.openssh = {
            enable = true;
            settings.PasswordAuthentication = true;
            settings.PermitRootLogin = "no";
          };

          # Enable mDNS for .local domain resolution
          services.avahi = {
            enable = true;
            nssmdns4 = true;
            publish = {
              enable = true;
              addresses = true;
              domain = true;
              hinfo = true;
              userServices = true;
              workstation = true;
            };
          };

          time.timeZone = "America/Los_Angeles";
          i18n.defaultLocale = "en_US.UTF-8";

          environment.systemPackages = with pkgs; [
            vim
            git
            htop
          ];

          hardware.enableRedistributableFirmware = true; # Hardware-specific settings
          system.stateVersion = "25.05";
        })
      ];
    };

    # Expose the SD card installer image for cross-compilation
    packages.${system}.default = self.nixosConfigurations.rpi5.config.system.build.sdImage;
  };
}
