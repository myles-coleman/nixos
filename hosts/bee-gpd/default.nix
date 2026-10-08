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
        # ./modules/egpu.nix
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
    networking.hostName = "bee-gpd";
    users.users.bee.extraGroups = ["video"];
    system.stateVersion = "25.05";
  };
}
