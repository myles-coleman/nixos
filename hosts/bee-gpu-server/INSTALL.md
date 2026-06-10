# Installation Guide for bee-gpu-server

## System Specs
- **CPU**: AMD Ryzen 5 5600X
- **GPU**: AMD Radeon RX 7900 XTX
- **RAM**: 24 GB
- **Desktop Environment**: KDE Plasma 6
- **Dual Boot**: Windows + NixOS

## Pre-Installation Steps

1. **Backup Windows data** if needed
2. **Shrink Windows partition** using Windows Disk Management to make space for NixOS
   - Recommended: At least 100GB for NixOS
3. **Download NixOS ISO** (25.05 or later) and create bootable USB
4. **Boot from USB** and start the NixOS installer

## Installation Steps

### 1. Partition Setup

If you're dual-booting, you should have:
- Existing EFI partition (from Windows)
- Existing Windows partition(s)
- New partition for NixOS root (/)
- Optional: Separate /home partition

Example partitioning:
```bash
# View existing partitions
lsblk

# Create partitions for NixOS (adjust device names as needed)
# Use gparted or parted to create:
# - One partition for / (root) - at least 50GB, ext4
# - Optional: One partition for /home - remaining space, ext4
```

### 2. Format and Mount

```bash
# Format root partition (replace /dev/nvmeXnYpZ with your actual partition)
mkfs.ext4 /dev/nvmeXnYpZ

# Mount root
mount /dev/nvmeXnYpZ /mnt

# Mount existing EFI partition (usually /dev/nvmeXnY1 or /dev/sdaY)
mkdir -p /mnt/boot
mount /dev/nvmeXnYp1 /mnt/boot  # Adjust to your EFI partition
```

### 3. Generate Hardware Configuration

```bash
# Generate initial config
nixos-generate-config --root /mnt

# Copy the hardware config to this repo's location
mkdir -p /mnt/etc/nixos
```

### 4. Clone This Repository

```bash
# If you have network access:
nix-shell -p git
cd /mnt/home
git clone https://github.com/yourusername/nixos.git  # Replace with your repo
cd nixos
```

### 5. Update Hardware Configuration

```bash
# Generate hardware config and save it
nixos-generate-config --show-hardware-config > /tmp/hw.nix

# Edit hosts/bee-gpu-server/hardware-configuration.nix
# Copy the contents from /tmp/hw.nix

# Important: Verify the following in hardware-configuration.nix:
# - Correct boot loader settings (EFI)
# - Correct filesystem UUIDs
# - AMD GPU drivers (amdgpu should be in boot.initrd.kernelModules)
```

### 6. Install NixOS

```bash
# From the cloned repo directory
sudo nixos-install --flake .#bee-gpu-server

# Set root password when prompted
# Create user password
sudo nixos-enter
passwd bee
exit
```

### 7. Post-Installation

```bash
# Reboot into NixOS
reboot

# After logging in, verify the configuration
cd ~/nixos
git status

# If everything looks good, commit the hardware config
git add hosts/bee-gpu-server/hardware-configuration.nix
git commit -m "Add hardware configuration for bee-gpu-server"

# Future updates: use the rebuild alias
rebuild
```

## GRUB Configuration Notes

The system is configured with:
- **GRUB bootloader** with EFI support
- **OS Prober enabled** to detect Windows automatically
- Both NixOS and Windows should appear in the boot menu

If Windows doesn't appear in GRUB:
```bash
# Edit hosts/bee-gpu-server/default.nix and ensure:
boot.loader.grub.useOSProber = true;

# Rebuild
rebuild
```

## AMD GPU Features

The configuration includes:
- **amdgpu** kernel module for GPU support
- **LACT** (Linux AMDGPU Configuration Tool) for GPU monitoring and control
- **Hardware acceleration** enabled
- **32-bit graphics** support for gaming

To monitor GPU:
```bash
# View GPU stats
amdgpu_top
# or
radeontop

# Or use LACT GUI
lact gui
```

## Plasma Desktop

The system uses KDE Plasma 6 with Wayland by default.

Pre-installed applications:
- Konsole (terminal)
- Dolphin (file manager)
- Kate (text editor)
- Gwenview (image viewer)
- Ark (archive manager)
- Spectacle (screenshots)
- Okular (document viewer)

## Modules Included

- `common.nix` - Base system configuration
- `plasma.nix` - KDE Plasma desktop environment
- `networking.nix` - Network configuration
- `dev-tools.nix` - Development tools
- `gaming.nix` - Steam, Lutris, gaming support
- `home.nix` - Home-manager integration

## Troubleshooting

### Windows partition not visible
```bash
# Mount manually (check partition UUID with lsblk -f)
# Uncomment and configure in hosts/bee-gpu-server/default.nix:
# fileSystems."/mnt/windows" = {
#   device = "/dev/disk/by-uuid/YOUR-WINDOWS-UUID";
#   fsType = "ntfs-3g";
#   options = [ "uid=1000" "gid=100" "umask=0002" "rw" ];
# };
```

### GPU not working
```bash
# Verify amdgpu module is loaded
lsmod | grep amdgpu

# Check kernel messages
dmesg | grep amdgpu
```

### GRUB not showing Windows
```bash
# Manually run os-prober
sudo os-prober

# Update GRUB
sudo nixos-rebuild switch --flake .#bee-gpu-server
```
