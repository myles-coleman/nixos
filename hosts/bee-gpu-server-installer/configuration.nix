# Custom NixOS installer for bee-gpu-server
# This creates a bootable ISO/SD image that contains your flake configuration
# and can automatically install to the target machine
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Make the installer more user-friendly
  services.openssh.enable = true;
  networking.wireless.enable = false; # Disable wireless, use NetworkManager instead
  networking.networkmanager.enable = true;

  # Include your flake configuration in the installer
  # The entire ~/nixos directory will be copied to /etc/nixos on the live system
  isoImage.storeContents = [
    # This includes the entire flake in the ISO
    (pkgs.runCommand "nixos-flake" {} ''
      mkdir -p $out/nixos
      cp -r ${./..}/* $out/nixos/
    '')
  ];

  # Convenient installer script
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    gptfdisk # for gdisk
    parted

    # Create a custom installation script
    (pkgs.writeScriptBin "install-bee-gpu-server" ''
      #!/usr/bin/env bash
      set -e

      echo "=== bee-gpu-server NixOS Installer ==="
      echo ""
      echo "This script will:"
      echo "  1. Help you partition your disk"
      echo "  2. Format partitions"
      echo "  3. Install NixOS with your flake configuration"
      echo ""
      echo "WARNING: This will ERASE ALL DATA on the target disk!"
      echo ""
      read -p "Continue? (yes/no): " confirm

      if [ "$confirm" != "yes" ]; then
        echo "Installation cancelled."
        exit 1
      fi

      echo ""
      echo "Available disks:"
      lsblk -d -o NAME,SIZE,MODEL
      echo ""
      read -p "Enter the disk to install to (e.g., nvme0n1, sda): " DISK

      DISK_PATH="/dev/$DISK"

      if [ ! -b "$DISK_PATH" ]; then
        echo "Error: $DISK_PATH is not a valid block device"
        exit 1
      fi

      echo ""
      echo "You selected: $DISK_PATH"
      lsblk "$DISK_PATH"
      echo ""
      read -p "This will ERASE $DISK_PATH. Type 'ERASE' to confirm: " erase_confirm

      if [ "$erase_confirm" != "ERASE" ]; then
        echo "Installation cancelled."
        exit 1
      fi

      echo ""
      echo "Creating partition table..."

      # Wipe existing partition table
      sgdisk --zap-all "$DISK_PATH"

      # Create GPT partition table and partitions
      # 1GB EFI partition
      sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK_PATH"
      # Rest of disk for root
      sgdisk -n 2:0:0 -t 2:8300 -c 2:"NixOS" "$DISK_PATH"

      # Inform kernel of partition changes
      partprobe "$DISK_PATH"
      sleep 2

      # Determine partition names (nvme uses p1, sda uses 1)
      if [[ "$DISK" == nvme* ]]; then
        PART1="''${DISK}p1"
        PART2="''${DISK}p2"
      else
        PART1="''${DISK}1"
        PART2="''${DISK}2"
      fi

      echo ""
      echo "Formatting partitions..."
      mkfs.fat -F 32 -n BOOT "/dev/$PART1"
      mkfs.ext4 -L nixos "/dev/$PART2"

      echo ""
      echo "Mounting filesystems..."
      mount "/dev/$PART2" /mnt
      mkdir -p /mnt/boot
      mount "/dev/$PART1" /mnt/boot

      echo ""
      echo "Generating hardware configuration..."
      nixos-generate-config --root /mnt

      echo ""
      echo "Installing NixOS with bee-gpu-server configuration..."

      # Copy the flake to /mnt/etc/nixos
      cp -r /etc/nixos/* /mnt/etc/nixos/ || true

      # Get the UUIDs for the newly created partitions
      BOOT_UUID=$(blkid -s UUID -o value "/dev/$PART1")
      ROOT_UUID=$(blkid -s UUID -o value "/dev/$PART2")

      echo ""
      echo "Partition UUIDs:"
      echo "  Boot: $BOOT_UUID"
      echo "  Root: $ROOT_UUID"
      echo ""
      echo "Please update /mnt/etc/nixos/hosts/bee-gpu-server/hardware-configuration.nix"
      echo "with these UUIDs before proceeding."
      echo ""
      read -p "Press Enter after updating hardware-configuration.nix..."

      # Install
      nixos-install --flake /mnt/etc/nixos#bee-gpu-server

      echo ""
      echo "Installation complete!"
      echo "Set root password and reboot when ready."
    '')
  ];

  # Add helpful message on login
  services.getty.helpLine = ''

    Welcome to the bee-gpu-server installer!

    Run 'install-bee-gpu-server' to begin installation.
    Or partition manually and run: nixos-install --flake /etc/nixos#bee-gpu-server

  '';
}
