# Building Custom NixOS Installer ISO

This repository now supports building a custom installer ISO for the `bee-gpu-server` machine.

## Quick Start

```bash
./build-installer.sh
```

This will:
1. Format all Nix code with alejandra
2. Build the custom installer ISO
3. Show you the location of the ISO file

## What Gets Built

The custom installer ISO includes:
- **Minimal NixOS live environment** (based on installation-cd-minimal)
- **Your complete flake configuration** pre-loaded at `/etc/nixos`
- **Automated installation script** (`install-bee-gpu-server`)
- **All necessary tools**: git, vim, parted, gdisk, etc.
- **NetworkManager** for easy network connectivity

## Writing to USB/SD Card

After building, write the ISO to a USB stick or SD card:

```bash
# Find your device
lsblk

# Write the image (replace /dev/sdX with your device)
sudo dd if=./result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**WARNING**: This will erase all data on the target device!

## Using the Installer

See [hosts/bee-gpu-server/INSTALLER.md](hosts/bee-gpu-server/INSTALLER.md) for detailed usage instructions.

### Quick Installation

1. Boot from the USB/SD card on bee-gpu-server
2. Run: `install-bee-gpu-server`
3. Follow the prompts
4. Set user password after installation
5. Reboot

## Manual Build Command

If you prefer not to use the script:

```bash
nix build .#bee-gpu-server-iso
```

The ISO will be at `./result/iso/nixos-*.iso`

## Customizing the Installer

Edit `hosts/bee-gpu-server-installer/configuration.nix` to customize:
- Included packages
- Installation script behavior  
- Network configuration
- SSH settings
- Any other installer-specific options

After changes, rebuild:
```bash
./build-installer.sh
```

## Flake Structure

The installer is defined in the flake:

```nix
nixosConfigurations.bee-gpu-server-installer = {
  # Installer system configuration
};

packages.x86_64-linux.bee-gpu-server-iso = {
  # Builds the ISO image
};
```

## Build Time

First build may take 10-30 minutes depending on your system and network speed. Subsequent builds will be much faster thanks to Nix caching.

## Size

The ISO is approximately 800MB-1GB in size (minimal installer with necessary tools).

## Troubleshooting

### Build fails with evaluation error

```bash
nix flake check  # Check for configuration errors
```

### Out of disk space

The build requires several GB of free space in `/nix/store`. Clean up:
```bash
nix-collect-garbage -d
```

### Want to test without writing to USB

Use QEMU to test the ISO:
```bash
nix-shell -p qemu --run "qemu-system-x86_64 -enable-kvm -m 4096 -cdrom ./result/iso/*.iso"
```

## Related Documentation

- [hosts/bee-gpu-server/INSTALLER.md](hosts/bee-gpu-server/INSTALLER.md) - Detailed installer usage guide
- [hosts/bee-gpu-server/README.md](hosts/bee-gpu-server/README.md) - bee-gpu-server configuration docs
