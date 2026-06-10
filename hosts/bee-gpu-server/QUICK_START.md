# Quick Start - Dual Boot Setup

## TL;DR - Fast Track

### Before You Start (Windows)
1. **Backup data**
2. **Disable Fast Startup**: Control Panel → Power Options → Choose what power buttons do → Uncheck "Turn on fast startup"
3. **Disable Secure Boot**: Reboot → BIOS (DEL/F2) → Security → Disable Secure Boot
4. **Shrink Windows**: Win+X → Disk Management → Right-click C: → Shrink Volume → 100000 MB → Shrink
5. **Create NixOS USB**: Download NixOS ISO → Use Rufus (GPT/UEFI mode)

### Installation (NixOS USB)
```bash
# 1. Partition (use cfdisk for easy GUI)
sudo cfdisk /dev/nvme0n1  # Select free space → New → Enter → Write → yes → Quit

# 2. Format
sudo mkfs.ext4 -L nixos /dev/nvme0n1p5  # Adjust partition number

# 3. Mount
sudo mount /dev/nvme0n1p5 /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/nvme0n1p1 /mnt/boot  # EFI partition (usually p1)

# 4. Generate config
sudo nixos-generate-config --root /mnt

# 5. Get your repo (if available online)
cd /mnt
sudo mkdir -p /mnt/home/bee
cd /mnt/home/bee
nix-shell -p git
sudo git clone YOUR_REPO_URL nixos
cd nixos

# 6. Update hardware config
sudo cp /mnt/etc/nixos/hardware-configuration.nix hosts/bee-gpu-server/hardware-configuration.nix

# 7. Install
sudo nixos-install --flake .#bee-gpu-server
# Enter root password when prompted

# 8. Set user password
sudo nixos-enter
passwd bee
exit

# 9. Reboot
sudo reboot
```

### First Boot
- Select NixOS or Windows from GRUB menu
- Log in as `bee` with your password
- Done! 🎉

---

## Alternative: If Repo Not Available Online

If you can't clone the repo during installation:

```bash
# After step 3 (mount), just install minimal then fix later:
sudo nixos-install --root /mnt

# After first boot into NixOS:
cd ~
git clone YOUR_REPO nixos
cd nixos

# Copy the hardware config from /etc/nixos
cp /etc/nixos/hardware-configuration.nix hosts/bee-gpu-server/hardware-configuration.nix

# Rebuild with your config
sudo nixos-rebuild switch --flake .#bee-gpu-server
```

---

## Troubleshooting One-Liners

```bash
# Windows not in GRUB?
sudo os-prober && sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server

# Windows partition read-only?
# Boot Windows → Disable Fast Startup → Full shutdown → Boot NixOS

# Check GPU working?
lsmod | grep amdgpu && amdgpu_top

# Mount Windows temporarily?
sudo mount -t ntfs-3g /dev/nvme0n1p3 /mnt/windows  # Adjust partition

# Rebuild system?
cd ~/nixos && rebuild
```

---

## Important Notes

- **EFI partition is SHARED** - Both Windows and NixOS use /dev/nvme0n1p1
- **GRUB is bootloader** - Installed by NixOS, automatically finds Windows
- **Don't format in Windows** - Only shrink, leave space unallocated
- **Disable Fast Startup** - Critical for proper dual boot

---

For detailed instructions, see: `DUAL_BOOT_GUIDE.md`
