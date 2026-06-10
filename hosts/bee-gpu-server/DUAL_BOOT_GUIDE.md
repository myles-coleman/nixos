# Complete Dual Boot Setup Guide - Windows + NixOS

## Overview
This guide will help you set up a dual boot system with Windows (existing) and NixOS (new) on bee-gpu-server.

---

## Phase 1: Prepare Windows (Do this FIRST, while in Windows)

### Step 1: Backup Important Data
- Back up all important files to external drive or cloud
- Create a Windows recovery USB (optional but recommended)
  - Settings → Update & Security → Recovery → Create a recovery drive

### Step 2: Disable Fast Startup (IMPORTANT!)
Fast Startup can cause issues with dual booting and NTFS access from Linux.

1. Open Control Panel → Power Options
2. Click "Choose what the power buttons do"
3. Click "Change settings that are currently unavailable"
4. **Uncheck "Turn on fast startup (recommended)"**
5. Save changes

### Step 3: Disable Secure Boot (if enabled)
1. Restart and enter BIOS/UEFI (usually press DEL, F2, or F12 during boot)
2. Find Security settings
3. **Disable Secure Boot** (NixOS can work with Secure Boot, but it's easier without)
4. Save and exit

### Step 4: Shrink Windows Partition
1. Press `Win + X` and select "Disk Management"
2. Right-click on your Windows partition (usually C:)
3. Select "Shrink Volume"
4. Enter amount to shrink:
   - **Minimum**: 50,000 MB (50 GB) for basic NixOS
   - **Recommended**: 100,000 MB (100 GB) for comfortable use
   - **Ideal**: 150,000+ MB (150+ GB) if you have space
5. Click "Shrink"
6. You should now see "Unallocated Space" - **DO NOT format this in Windows**

### Step 5: Note Your Disk Configuration
In Disk Management, note down:
- Which disk Windows is on (Disk 0, Disk 1, etc.)
- Size of your disks
- The EFI System Partition (usually 100-500 MB, FAT32)
- Take a screenshot for reference

---

## Phase 2: Create NixOS Installation Media

### Download NixOS
1. Download NixOS ISO from: https://nixos.org/download.html
   - Get the **Plasma Desktop** ISO (since you're using Plasma)
   - Or get the minimal ISO (you already have Plasma in your config)
   - Use version 25.05 or newer

### Create Bootable USB
**On Windows:**
- Use Rufus (https://rufus.ie/)
- Select your USB drive (at least 8GB)
- Select the NixOS ISO
- Partition scheme: **GPT**
- Target system: **UEFI (non CSM)**
- Click Start

**On Linux:**
```bash
# Check your USB device name
lsblk

# Write ISO to USB (replace /dev/sdX with your USB device)
sudo dd if=nixos.iso of=/dev/sdX bs=4M status=progress && sync
```

---

## Phase 3: Boot into NixOS Installer

### Step 1: Boot from USB
1. Insert USB drive
2. Restart computer
3. Press boot menu key (usually F12, F11, F8, or ESC)
4. Select your USB drive from the list
5. Select "NixOS Installer" from the boot menu

### Step 2: Connect to Network (if needed)
```bash
# For WiFi
sudo systemctl start wpa_supplicant
wpa_cli

# In wpa_cli:
> add_network
0
> set_network 0 ssid "YourWiFiName"
> set_network 0 psk "YourWiFiPassword"
> enable_network 0
> quit

# For Ethernet - should work automatically
ip addr  # Verify you have an IP
```

---

## Phase 4: Partition Setup for NixOS

### Step 1: Identify Your Disks
```bash
# List all disks and partitions
lsblk

# More detailed info
sudo fdisk -l

# Example output:
# /dev/nvme0n1      (your main SSD)
# ├─/dev/nvme0n1p1  (EFI partition - 500M)
# ├─/dev/nvme0n1p2  (Windows reserved - 16M)
# ├─/dev/nvme0n1p3  (Windows C: - 200G)
# └─/dev/nvme0n1p4  (Free space - 100G)  ← We'll use this
```

### Step 2: Partition the Free Space
You have two options:

**Option A: Simple Layout (Recommended for beginners)**
- One partition for everything (root)

**Option B: Separate Home (Recommended for experienced users)**
- One partition for system (/)
- One partition for home (/home)

#### Using `cfdisk` (Easier, recommended)
```bash
# Start cfdisk on your main disk
sudo cfdisk /dev/nvme0n1  # or /dev/sda if you use SATA

# You should see your unallocated space
# Navigate to the free space with arrow keys
```

**For Option A (Simple Layout):**
```bash
# In cfdisk:
1. Select [New]
2. Press Enter to use all available space
3. Type should be "Linux filesystem"
4. Select [Write] and type "yes" to confirm
5. Select [Quit]
```

**For Option B (Separate Home):**
```bash
# In cfdisk:
# Create root partition (40-60GB)
1. Select [New]
2. Enter: 50G
3. Type: Linux filesystem

# Create home partition (remaining space)
4. Navigate to remaining free space
5. Select [New]
6. Press Enter (use all remaining)
7. Type: Linux filesystem

8. Select [Write] and type "yes"
9. Select [Quit]
```

### Step 3: Format the New Partitions
```bash
# Check your new partition names
lsblk

# Assuming your new partitions are nvme0n1p5 (and nvme0n1p6 for home)
# Format root partition as ext4
sudo mkfs.ext4 -L nixos /dev/nvme0n1p5

# If you created a separate home partition:
sudo mkfs.ext4 -L nixos-home /dev/nvme0n1p6
```

---

## Phase 5: Mount Partitions

### Step 1: Mount Root
```bash
# Mount the root partition
sudo mount /dev/nvme0n1p5 /mnt
```

### Step 2: Mount EFI Partition (SHARED with Windows)
```bash
# Create boot directory
sudo mkdir -p /mnt/boot

# Mount the EXISTING EFI partition (same one Windows uses)
# This is usually the first partition (nvme0n1p1 or sda1)
# Check with: sudo fdisk -l | grep EFI
sudo mount /dev/nvme0n1p1 /mnt/boot
```

### Step 3: Mount Home (if separate)
```bash
# Only if you created a separate home partition
sudo mkdir -p /mnt/home
sudo mount /dev/nvme0n1p6 /mnt/home
```

### Verify Mounts
```bash
# Check everything is mounted correctly
mount | grep /mnt

# Should show:
# /dev/nvme0n1p5 on /mnt type ext4
# /dev/nvme0n1p1 on /mnt/boot type vfat
# /dev/nvme0n1p6 on /mnt/home type ext4 (if separate home)
```

---

## Phase 6: Install NixOS

### Step 1: Generate Hardware Config
```bash
# Generate initial configuration
sudo nixos-generate-config --root /mnt

# This creates:
# /mnt/etc/nixos/configuration.nix
# /mnt/etc/nixos/hardware-configuration.nix
```

### Step 2: Clone Your NixOS Repository
```bash
# Install git (temporary, for installation)
nix-shell -p git

# Clone your repo
cd /mnt
sudo mkdir -p /mnt/home/bee
cd /mnt/home/bee
sudo git clone https://github.com/YOUR_USERNAME/nixos.git  # Replace with your repo URL

# If you don't have it pushed yet, you can copy from USB or use the generated config
```

### Step 3: Update Hardware Configuration
```bash
# Copy the generated hardware config to your repo
cd /mnt/home/bee/nixos
sudo cp /mnt/etc/nixos/hardware-configuration.nix hosts/bee-gpu-server/hardware-configuration.nix

# View and verify it
cat hosts/bee-gpu-server/hardware-configuration.nix
```

**IMPORTANT: Verify the hardware-configuration.nix contains:**
- Correct filesystem UUIDs (should match your new partitions)
- EFI partition mounted at /boot
- amdgpu in boot.initrd.kernelModules or boot.kernelModules

### Step 4: Check Your Flake Configuration
```bash
# Verify your flake is valid
cd /mnt/home/bee/nixos
nix flake check --no-build
```

### Step 5: Install NixOS
```bash
# Install from your flake
cd /mnt/home/bee/nixos
sudo nixos-install --flake .#bee-gpu-server

# This will:
# - Build the system
# - Install it to /mnt
# - Install GRUB to the EFI partition
# - Detect Windows (via os-prober)

# When prompted, set a password for root
```

### Step 6: Set User Password
```bash
# Enter the new system
sudo nixos-enter

# Set password for your user
passwd bee

# Exit
exit
```

---

## Phase 7: First Boot

### Step 1: Reboot
```bash
# Remove USB drive
# Reboot
sudo reboot
```

### Step 2: GRUB Boot Menu
You should see GRUB with options:
- **NixOS** (default)
- **Windows Boot Manager** (your Windows installation)
- Advanced options

Select NixOS to boot into your new system!

### Step 3: Log In
- Username: `bee`
- Password: (what you set earlier)
- Desktop: KDE Plasma should start automatically

---

## Phase 8: Post-Installation Configuration

### Step 1: Verify Dual Boot Works
```bash
# Reboot and test Windows
sudo reboot

# Select "Windows Boot Manager" from GRUB menu
# Verify Windows still works

# Reboot back to NixOS
```

### Step 2: If Windows Doesn't Appear in GRUB

```bash
# In NixOS, update GRUB
sudo nix-shell -p os-prober
sudo os-prober

# Should output Windows Boot Manager location
# If it finds Windows, rebuild:
sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server

# Reboot to see updated GRUB menu
```

### Step 3: Mount Windows Partition in NixOS (Optional)
If you want to access Windows files from NixOS:

```bash
# Find your Windows partition UUID
lsblk -f

# Edit your config
cd ~/nixos
# Add this to hosts/bee-gpu-server/default.nix:
```

```nix
# Uncomment and configure:
fileSystems."/mnt/windows" = {
  device = "/dev/disk/by-uuid/YOUR-WINDOWS-PARTITION-UUID";  # Get from lsblk -f
  fsType = "ntfs-3g";
  options = [ "uid=1000" "gid=100" "umask=0002" "rw" ];
};
```

```bash
# Rebuild
rebuild
```

### Step 4: Configure Your System
```bash
cd ~/nixos

# Make any configuration changes you want
# Edit files in hosts/bee-gpu-server/

# Apply changes
rebuild
```

---

## Troubleshooting

### GRUB doesn't show Windows
```bash
# Enable os-prober verbose output
sudo os-prober

# If it finds Windows but GRUB doesn't show it:
# Verify in hosts/bee-gpu-server/default.nix:
boot.loader.grub.useOSProber = true;

# Rebuild
sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server
```

### Windows partition is read-only
This happens if Windows used Fast Startup:
```bash
# Boot into Windows
# Disable Fast Startup (see Phase 1, Step 2)
# Shutdown Windows completely (not restart)
# Boot back to NixOS
```

### Can't boot into Windows
- Enter BIOS and check boot order
- Make sure EFI partition is intact
- Try using BIOS boot menu (F12/F11) to manually select Windows

### AMD GPU not detected
```bash
# Check if module is loaded
lsmod | grep amdgpu

# Check dmesg for errors
dmesg | grep amdgpu

# Verify in hardware-configuration.nix:
boot.initrd.kernelModules = [ "amdgpu" ];
```

### Need to access Windows files
```bash
# Mount Windows partition temporarily
sudo mkdir -p /mnt/windows
sudo mount -t ntfs-3g /dev/nvme0n1p3 /mnt/windows  # Adjust partition number

# Browse files
ls /mnt/windows
```

---

## Default Boot Order

By default, GRUB will boot NixOS after 5 seconds.

To change default boot option:
```nix
# In hosts/bee-gpu-server/default.nix, add:
boot.loader.grub.default = "saved";  # Remember last selection
# or
boot.loader.grub.default = 2;  # Specific menu entry (0-indexed)
```

To change timeout:
```nix
boot.loader.timeout = 10;  # Wait 10 seconds before auto-boot
```

---

## Quick Reference

### Boot Keys (when starting computer)
- **Boot Menu**: F12, F11, F8, or ESC (depends on motherboard)
- **BIOS/UEFI**: DEL, F2, or F10
- **AMD Motherboard**: Usually DEL or F2

### Important Partitions
- **EFI**: Shared between Windows and NixOS (FAT32, 100-500MB)
- **Windows**: Your existing Windows partition (NTFS)
- **NixOS Root**: New Linux partition (ext4)
- **NixOS Home**: Optional separate partition (ext4)

### Key Commands
```bash
# List disks
lsblk
lsblk -f  # with filesystems and UUIDs

# Rebuild NixOS
rebuild

# Rebuild with flake path
sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server

# Update GRUB menu
sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server
```

---

## Summary of Dual Boot Setup

1. ✅ Disable Fast Startup and Secure Boot in Windows
2. ✅ Shrink Windows partition to make space
3. ✅ Boot NixOS installer USB
4. ✅ Create Linux partition(s) in free space
5. ✅ Mount partitions (including shared EFI)
6. ✅ Install NixOS with your flake configuration
7. ✅ GRUB automatically installed to EFI partition
8. ✅ OS Prober detects Windows
9. ✅ Reboot and select OS from GRUB menu
10. ✅ Both systems work independently

The key to dual boot is:
- **Shared EFI partition**: Both OSes use the same /boot partition
- **GRUB as bootloader**: Installed by NixOS, detects Windows
- **Separate OS partitions**: Windows on NTFS, NixOS on ext4
- **OS Prober**: Automatically finds Windows and adds to GRUB menu
