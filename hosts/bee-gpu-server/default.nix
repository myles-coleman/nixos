{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./home
  ];

  # Dual-boot configuration with Windows
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    useOSProber = true; # Detect Windows and other OS
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "bee-gpu-server";

  # AMD GPU support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # AMD specific packages
  environment.systemPackages = with pkgs; [
    amdgpu_top
    radeontop
    lact # Linux AMDGPU Configuration Tool
  ];

  # Enable LACT service for AMD GPU control
  systemd.packages = with pkgs; [lact];
  systemd.services.lactd = {
    description = "AMDGPU Control Daemon";
    enable = true;
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
    wantedBy = ["multi-user.target"];
  };

  system.stateVersion = "25.05";
}
