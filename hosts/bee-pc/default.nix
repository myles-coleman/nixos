{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  networking.hostName = "bee-pc";

  programs.zsh.shellAliases = {
    windsurf = "windsurf 2>/dev/null"; # hide windsurf warnings
  };

  environment.systemPackages = with pkgs; [
    obs-studio
    obs-studio-plugins.obs-vkcapture
    unstable.rpi-imager
    r2modman
    goverlay
    xorg.libX11
    nerd-fonts.meslo-lg
    meslo-lgs-nf
    font-awesome
    material-icons
    material-design-icons
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
}
