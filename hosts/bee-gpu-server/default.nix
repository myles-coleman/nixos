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

  # Note: systemd-boot doesn't auto-detect Windows like GRUB does
  # Windows should still be bootable via UEFI firmware boot menu
  # Press F12/F11 during boot to select Windows manually
  # Or add manual entry (see comments below)

  # Optional: Limit number of generations to save space
  boot.loader.systemd-boot.configurationLimit = 10;

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

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  system.stateVersion = "25.05";
}
