{
  config,
  inputs,
  ...
}: let
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  flake.modules.nixos.bee-pc = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports =
      [
        ./hardware-configuration.nix
        ./home
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.default
      ]
      ++ (with aspects; [
        common
        desktop
        home-desktop
        home-zsh
        network
        dev-tools
        gaming
        unstable
      ]);

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.binfmt.emulatedSystems = ["aarch64-linux"];

    networking.hostName = "bee-pc";

    # Fonts come from the `desktop` aspect's `fonts.packages`; only the
    # non-font host-local packages remain here.
    environment.systemPackages = with pkgs; [
      obs-studio
      obs-studio-plugins.obs-vkcapture
      unstable.rpi-imager
      r2modman
      goverlay
      xorg.libX11
      unstable.opencode
      ripgrep
    ];

    # fileSystems."/mnt/harddrive" = {
    #   device = "UUID=060C52F50C52DEED";
    #   fsType = "ntfs-3g";
    #   options = ["uid=1000" "gid=100" "umask=0002"];
    # };

    # fileSystems."/mnt/backup" = {
    #   device = "UUID=01DA7976C02A2420";
    #   fsType = "ntfs-3g";
    #   options = ["uid=1000" "gid=100" "umask=0002"];
    # };

    system.stateVersion = "25.05";
  };
}
