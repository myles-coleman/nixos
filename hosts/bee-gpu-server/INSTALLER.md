# Custom Installer ISO for bee-gpu-server

This directory includes configuration for building a custom NixOS installer that contains your complete bee-gpu-server configuration.

## Why Use a Custom Installer?

Instead of using the generic NixOS installer and manually setting up everything, this custom ISO:
- Contains your entire flake configuration pre-loaded
- Includes an automated installation script
- Has all necessary tools pre-installed
- Saves time on repeated installations

## Building the ISO

From the nixos repository root:

```bash
./build-installer.sh
```

Or manually:

```bash
nix build .#bee-gpu-server-iso
```

The ISO will be created at `./result/iso/nixos-*.iso`

## Writing to USB/SD Card

### Find your device

```bash
lsblk
```

### Write the image

```bash
sudo dd if=./result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your actual USB/SD device (e.g., `/dev/sdb`).

**WARNING**: This will erase all data on the target device!

## Using the Installer

1. **Boot from the USB/SD card**
   - Insert the USB/SD into bee-gpu-server
   - Boot from it (may need to select boot device in BIOS)

2. **Run the automated installer**
   ```bash
   install-bee-gpu-server
   ```
   
   This script will:
   - Prompt you to select the target disk
   - Partition the disk (1GB EFI + rest for root)
   - Format partitions
   - Generate hardware-configuration.nix
   - Pause for you to update UUIDs
   - Run nixos-install with your flake

3. **Or install manually**
   ```bash
   # Partition disk manually
   gdisk /dev/nvme0n1
   
   # Format partitions
   mkfs.fat -F 32 /dev/nvme0n1p1
   mkfs.ext4 /dev/nvme0n1p2
   
   # Mount
   mount /dev/nvme0n1p2 /mnt
   mkdir -p /mnt/boot
   mount /dev/nvme0n1p1 /mnt/boot
   
   # Generate config
   nixos-generate-config --root /mnt
   
   # Copy flake (already in /etc/nixos from the ISO)
   cp -r /etc/nixos/* /mnt/etc/nixos/
   
   # Update hardware-configuration.nix with correct UUIDs
   vim /mnt/etc/nixos/hosts/bee-gpu-server/hardware-configuration.nix
   
   # Install
   nixos-install --flake /mnt/etc/nixos#bee-gpu-server
   ```

4. **Set passwords and reboot**
   ```bash
   nixos-enter --root /mnt
   passwd bee
   exit
   reboot
   ```

## Customizing the Installer

The installer configuration is in:
- `hosts/bee-gpu-server-installer/configuration.nix`

You can customize:
- Included packages
- Installation script behavior
- SSH access
- Kernel modules
- Any other installer-specific settings

## Updating the Installer

After making changes to your bee-gpu-server configuration, rebuild the ISO:

```bash
./build-installer.sh
```

This ensures the installer always contains your latest configuration.

## Troubleshooting

### ISO build fails

Make sure all your configurations are valid:
```bash
nix flake check
```

### Installer can't find flake

The flake is copied to `/etc/nixos` in the live environment. Verify:
```bash
ls -la /etc/nixos
```

### Installation fails with UUID errors

Make sure you updated `hosts/bee-gpu-server/hardware-configuration.nix` with the UUIDs from `blkid` after partitioning.
