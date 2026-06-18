# Deploying bee-gpu-server

This guide follows the same straightforward approach as the homelab deployment.

## Prerequisites

- NixOS installer USB (standard official NixOS installer is fine)
- Network connectivity on the target machine

## Step 1: Boot NixOS Installer

Boot the target machine from the NixOS installer USB.

## Step 2: Partition the Disk

```bash
# Use gdisk for GPT partitioning
sudo gdisk /dev/nvme0n1

# Create partitions:
# - 1GB EFI partition (type ef00)
# - Remaining space for root (type 8300)

# Format partitions
sudo mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
sudo mkfs.ext4 -L nixos /dev/nvme0n1p2

# Mount
sudo mount /dev/nvme0n1p2 /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/nvme0n1p1 /mnt/boot
```

## Step 3: Generate Hardware Config

```bash
sudo nixos-generate-config --root /mnt
```

## Step 4: Transfer Your Flake

```bash
# Clone your nixos repository
git clone https://github.com/YOUR_USERNAME/nixos /tmp/nixos

# Or transfer via USB, scp, etc.

# Copy to /mnt/etc/nixos
sudo cp -r /tmp/nixos/* /mnt/etc/nixos/
```

## Step 5: Update Hardware Configuration

```bash
# Get the UUIDs of your partitions
sudo blkid

# Edit the hardware config with the correct UUIDs
sudo nano /mnt/etc/nixos/hosts/bee-gpu-server/hardware-configuration.nix

# Update:
# - Boot partition UUID (the FAT32 one)
# - Root partition UUID (the ext4 one)
```

## Step 6: Install

```bash
sudo nixos-install --flake /mnt/etc/nixos#bee-gpu-server
```

## Step 7: Set User Password

```bash
sudo nixos-enter --root /mnt
passwd bee
exit
```

## Step 8: Reboot

```bash
sudo reboot
```

## Post-Installation

After booting into the installed system:

1. **Set up git if needed**:
   ```bash
   # Edit your git email in the config
   sudo nano /etc/nixos/hosts/bee-gpu-server/home/default.nix
   # Update the userEmail field
   ```

2. **Clone your nixos repository**:
   ```bash
   cd ~
   git clone https://github.com/YOUR_USERNAME/nixos
   cd nixos
   ```

3. **Future updates**:
   ```bash
   # Make changes to the configuration
   rebuild
   # (or: sh ~/nixos/rebuild.sh)
   ```

4. **Connect to Tailscale**:
   ```bash
   sudo tailscale up
   ```

5. **Authenticate with GitHub** (if needed):
   ```bash
   gh auth login
   ```

## Remote Deployment (from another machine)

Once the machine is set up and reachable via SSH:

```bash
# From your main machine (bee-gpd)
cd ~/nixos
./rebuild.sh --target bee@bee-gpu-server
```

The passwordless sudo configured in the host ensures smooth remote deployments.

## Troubleshooting

### Installation fails with flake errors

Make sure the flake is in `/mnt/etc/nixos` and contains a `flake.nix` file.

### Boot fails

Check that the UUIDs in `hardware-configuration.nix` match your actual partitions (`sudo blkid`).

### Can't SSH after installation

Make sure you set a password for the `bee` user in step 7.
