{
  config,
  inputs,
  ...
}: let
  aspects = config.flake.modules.nixos;
in {
  flake.modules.nixos.bee-gpd = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports =
      [
        ./hardware-configuration.nix
        ./home
        ./modules/egpu.nix
        ./modules/input.nix
        ./modules/automation.nix
        ./modules/networking.nix
        ./modules/packages.nix
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.default
      ]
      ++ (with aspects; [
        access
        common
        desktop
        home-desktop
        home-zsh
        network
        dev-tools
        gaming
        nvidia
        unstable
      ]);

    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 1;
    boot.loader.efi.canTouchEfiVariables = true;

    # Allow running armv6l binaries via QEMU (for cross-deploying to RPi 1)
    boot.binfmt.emulatedSystems = ["armv6l-linux"];

    networking.hostName = "bee-gpd";

    # Extra groups specific to bee-gpd
    users.users.bee.extraGroups = ["video"];

    system.stateVersion = "25.05";
  };
}
