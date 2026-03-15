# TODO: Replace with output of `nixos-generate-config --show-hardware-config`
# after booting the NixOS installer on the homelab machine.
#
# This is a placeholder based on the current Ubuntu layout:
# - NVMe: nvme0n1 (LVM, BIOS/Legacy)
# - RAID10: md0 (sda, sdb, sdc, sdd)
# - Intel Arc A310 GPU
# - Realtek RTL8125 2.5GbE + RTL8852CE WiFi
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

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = ["dm-mod"];
  boot.kernelModules = ["kvm-amd" "raid10"];
  boot.extraModulePackages = [];

  # NVMe root (LVM) — UUIDs will change after NixOS install
  # fileSystems."/" = {
  #   device = "/dev/ubuntu-vg/ubuntu-lv";
  #   fsType = "ext4";
  # };
  #
  # fileSystems."/boot" = {
  #   device = "/dev/disk/by-uuid/XXXX";
  #   fsType = "ext4";
  # };

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
