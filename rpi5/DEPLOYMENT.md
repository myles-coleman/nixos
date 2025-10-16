# Deploying NixOS to Raspberry Pi 5 with nixos-anywhere

## Overview
This guide will help you deploy NixOS to your Raspberry Pi 5 using `nixos-anywhere`. Since kexec is not supported on Raspberry Pi, you'll need to boot from a NixOS installer image first.

## Prerequisites
- Raspberry Pi 5 with SSD attached
- SD card for the installer image
- Network connection to the Pi at `10.0.0.141`

## Step 1: Build the NixOS Installer Image

First, build the installer SD card image from the nixos-raspberrypi flake:

```bash
# Build the RPi5 installer image
nix build github:nvmd/nixos-raspberrypi#installerImages.rpi5
```

This will create a `.img.zst` file in `./result/sd-image/`.

## Step 2: Flash the Installer Image to SD Card

**IMPORTANT**: Make sure you identify the correct SD card device. In your case, it appears to be `/dev/sdd`.

```bash
# Decompress and flash the image
zstd -d ./result/sd-image/*.img.zst -c | sudo dd of=/dev/sdd bs=4M status=progress conv=fsync
```

## Step 3: Boot Raspberry Pi from the Installer SD Card

1. Remove the SD card from your computer
2. Insert it into your Raspberry Pi 5
3. Boot the Pi from the SD card
4. The installer will display randomly generated SSH credentials on screen
5. Note the hostname (should be accessible via mDNS as `nixos.local` or at `10.0.0.141`)

## Step 4: Configure the Disk Device Path

**CRITICAL**: Before running nixos-anywhere, you need to verify the device path of your SSD on the Pi.

SSH into the installer:
```bash
ssh root@10.0.0.141
# or
ssh root@nixos.local
```

Then check the available disks:
```bash
lsblk
```

Look for your SSD (it might be `/dev/sda`, `/dev/nvme0n1`, or something else). Then update `disko-config.nix` with the correct device path.

## Step 5: Update disko-config.nix

Edit `/home/bee/nixos/rpi5/disko-config.nix` and change the `device` line to match your SSD:

```nix
device = "/dev/sda";  # Change this to your actual SSD device
```

## Step 6: Run nixos-anywhere

Now you can deploy NixOS to your Pi:

```bash
nixos-anywhere --flake .#rpi5 root@10.0.0.141
```

Or if using mDNS:
```bash
nixos-anywhere --flake .#rpi5 root@nixos.local
```

### Additional Options

If you want to copy your SSH host keys:
```bash
nixos-anywhere --flake .#rpi5 --copy-host-keys root@10.0.0.141
```

If you want to see full build logs:
```bash
nixos-anywhere --flake .#rpi5 --print-build-logs root@10.0.0.141
```

If you want to build on the remote machine (slower but uses less local resources):
```bash
nixos-anywhere --flake .#rpi5 --build-on-remote root@10.0.0.141
```

## Step 7: After Installation

After `nixos-anywhere` completes:

1. The Pi will automatically reboot
2. Remove the SD card (the system will now boot from the SSD)
3. Wait for the system to come back online
4. SSH into your new NixOS system:
   ```bash
   ssh pi@10.0.0.141
   # Password: raspberry (as configured in flake.nix)
   ```

## What nixos-anywhere Does

1. Connects to the installer via SSH
2. Partitions and formats your SSD according to `disko-config.nix`
3. Installs NixOS with your configuration from `flake.nix`
4. Reboots the system

## Troubleshooting

### Can't connect to the installer
- Make sure the Pi is on the same network
- Try using mDNS: `ssh root@nixos.local`
- Check the screen for the correct IP address and credentials

### Wrong disk device
- SSH into the installer and run `lsblk` to identify the correct device
- Update `disko-config.nix` with the correct path

### Build fails
- Make sure you have enough disk space
- Try building with `--print-build-logs` to see detailed errors
- Consider using `--build-on-remote` if your local machine is low on resources

## Future Updates

After the initial installation, you can update your Pi's configuration by:

```bash
nixos-rebuild switch --flake .#rpi5 --target-host pi@10.0.0.141 --use-remote-sudo
```

Or run nixos-anywhere again (it will reformat the disk, so only do this if you want a fresh install).
