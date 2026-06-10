# This is a placeholder hardware configuration file.
# After installing NixOS on bee-gpu-server, run the following command to generate the actual hardware config:
# sudo nixos-generate-config --show-hardware-config > /home/bee/nixos/hosts/bee-gpu-server/hardware-configuration.nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Placeholder configuration for Ryzen 5 5600X with AMD RX 7900 XTX
  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = ["amdgpu"];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # Placeholder filesystem configuration
  # NOTE: Replace these with actual partition UUIDs after installation
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
    fsType = "vfat";
  };

  # Example for mounting Windows partition (optional)
  # fileSystems."/mnt/windows" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-WINDOWS-UUID";
  #   fsType = "ntfs-3g";
  #   options = [ "uid=1000" "gid=100" "umask=0002" "rw" ];
  # };

  # AMD CPU microcode
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Enable 32-bit support for gaming
  hardware.graphics.enable32Bit = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
