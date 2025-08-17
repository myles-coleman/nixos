{
  description = "NixOS configuration for Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
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
  } @ inputs: let
    system = "x86_64-linux"; # build system architecture
    targetSystem = "aarch64-linux"; # target architecture
  in {
    packages.${system}.default = nixos-raspberrypi.installerImages.rpi5;

    nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystem {
      inherit system;
      specialArgs = inputs;
      modules = [
        ({...}: {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.bluetooth
          ];
          boot.binfmt.emulatedSystems = ["aarch64-linux"]; # for cross-compilation
        })

        {
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

          time.timeZone = "America/Los_Angeles";
          i18n.defaultLocale = "en_US.UTF-8";

          environment.systemPackages = with nixpkgs.legacyPackages.${targetSystem}; [
            vim
            git
            htop
          ];

          hardware.enableRedistributableFirmware = true; # Hardware-specific settings
          system.stateVersion = "25.05"; # This is required for the SD image
        }
      ];
    };
  };
}
