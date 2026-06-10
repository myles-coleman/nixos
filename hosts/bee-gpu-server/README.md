# bee-gpu-server - NixOS Configuration

NixOS configuration for bee-gpu-server: A dual-boot system with Windows and NixOS.

---

## System Specifications

- **Hostname**: bee-gpu-server
- **CPU**: AMD Ryzen 5 5600X
- **GPU**: AMD Radeon RX 7900 XTX
- **RAM**: 24 GB
- **Architecture**: x86_64-linux
- **Desktop Environment**: KDE Plasma 6 (Wayland)
- **Display Manager**: SDDM
- **Boot**: Dual boot with Windows (GRUB + OS Prober)

---

## Features

### Desktop Environment
- **KDE Plasma 6** with Wayland support
- SDDM login manager
- Full KDE application suite (Dolphin, Kate, Konsole, etc.)
- Plasma Browser Integration
- KDE Connect support

### AMD GPU Support
- AMD GPU drivers (amdgpu)
- Hardware acceleration enabled
- 32-bit graphics support for gaming
- GPU monitoring tools:
  - `amdgpu_top` - Real-time GPU stats
  - `radeontop` - GPU monitoring
  - `lact` - Linux AMDGPU Configuration Tool (GUI)

### System Features
- **Dual boot** with Windows (GRUB bootloader)
- **Gaming support** (Steam, Lutris, GameMode)
- **Development tools** (Git, Docker, build tools)
- **Audio**: PipeWire with ALSA, PulseAudio, and JACK support
- **Bluetooth**: Full Bluetooth stack enabled
- **Networking**: NetworkManager with GUI

### Included Modules
- `common.nix` - Base system (packages, users, Docker, etc.)
- `plasma.nix` - KDE Plasma desktop environment
- `networking.nix` - Network configuration
- `dev-tools.nix` - Development environment
- `gaming.nix` - Steam, Lutris, gaming optimizations
- `home.nix` - Home-manager integration

---

## Documentation

### Installation & Setup
1. **[CHECKLIST.md](./CHECKLIST.md)** - Pre-installation checklist (start here!)
2. **[DUAL_BOOT_GUIDE.md](./DUAL_BOOT_GUIDE.md)** - Complete dual boot setup guide
3. **[QUICK_START.md](./QUICK_START.md)** - TL;DR quick reference
4. **[PARTITION_LAYOUT.md](./PARTITION_LAYOUT.md)** - Visual partition layout guide
5. **[INSTALL.md](./INSTALL.md)** - Technical installation reference

### Recommended Reading Order
1. Read **CHECKLIST.md** first
2. Follow **DUAL_BOOT_GUIDE.md** during installation
3. Keep **QUICK_START.md** handy for commands
4. Refer to **PARTITION_LAYOUT.md** if confused about disks

---

## Quick Commands

### Rebuild System
```bash
# Local rebuild (auto-detects hostname)
rebuild

# With flake path
sudo nixos-rebuild switch --flake /home/bee/nixos#bee-gpu-server

# Dry run (test without applying)
rebuild --dry-run
```

### GPU Monitoring
```bash
# Real-time GPU stats
amdgpu_top

# Alternative monitoring
radeontop

# GUI configuration tool
lact gui
```

### Check Dual Boot
```bash
# Verify Windows is detected
sudo os-prober

# Update GRUB if Windows not showing
sudo nixos-rebuild switch --flake .#bee-gpu-server
```

### Mount Windows Partition
```bash
# Temporarily
sudo mount -t ntfs-3g /dev/nvme0n1p3 /mnt/windows

# Permanently: Edit default.nix and add to fileSystems
```

---

## File Structure

```
bee-gpu-server/
├── README.md                      # This file
├── CHECKLIST.md                   # Pre-installation checklist
├── DUAL_BOOT_GUIDE.md            # Complete setup guide
├── QUICK_START.md                # Quick reference
├── PARTITION_LAYOUT.md           # Disk layout visualization
├── INSTALL.md                    # Technical install docs
├── default.nix                   # Host configuration
├── hardware-configuration.nix    # Hardware-specific config (generated)
└── home/
    └── default.nix               # Home-manager configuration
```

---

## Configuration Highlights

### Boot Loader (default.nix)
```nix
boot.loader.grub = {
  enable = true;
  device = "nodev";
  efiSupport = true;
  useOSProber = true;  # Detects Windows
};
```

### AMD GPU (default.nix)
```nix
hardware.graphics = {
  enable = true;
  enable32Bit = true;
};

# LACT service for GPU control
systemd.services.lactd = {
  description = "AMDGPU Control Daemon";
  enable = true;
  # ...
};
```

### Desktop (modules/plasma.nix)
```nix
services.displayManager.sddm.enable = true;
services.displayManager.sddm.wayland.enable = true;
services.desktopManager.plasma6.enable = true;
```

---

## First Time Setup

After installation:

1. **Update hardware-configuration.nix**
   ```bash
   # Generate on the actual machine
   sudo nixos-generate-config --show-hardware-config > ~/nixos/hosts/bee-gpu-server/hardware-configuration.nix
   ```

2. **Verify dual boot works**
   - Reboot and check GRUB menu
   - Test both NixOS and Windows

3. **Optional: Mount Windows partition**
   - Get UUID: `lsblk -f`
   - Add to `default.nix` under `fileSystems`
   - Rebuild: `rebuild`

4. **Configure Plasma**
   - Set theme, wallpaper, etc.
   - Settings are automatically saved

5. **Test GPU**
   ```bash
   lsmod | grep amdgpu  # Should show loaded module
   amdgpu_top           # Should show GPU stats
   ```

---

## Troubleshooting

### Windows not in GRUB menu
```bash
sudo os-prober
sudo nixos-rebuild switch --flake .#bee-gpu-server
```

### GPU not detected
```bash
# Check module loaded
lsmod | grep amdgpu

# Check hardware-configuration.nix has:
boot.initrd.kernelModules = [ "amdgpu" ];
```

### Windows partition read-only
- Boot into Windows
- Disable Fast Startup (Control Panel → Power Options)
- Shutdown (not restart)
- Boot back to NixOS

### LACT service not starting
```bash
# Check status
systemctl status lactd

# Restart service
sudo systemctl restart lactd
```

---

## Customization

### Change GRUB timeout
Add to `default.nix`:
```nix
boot.loader.timeout = 10;  # Wait 10 seconds
```

### Remember last OS choice
Add to `default.nix`:
```nix
boot.loader.grub.default = "saved";
```

### Add more KDE apps
Edit `home/default.nix`:
```nix
home.packages = with pkgs; [
  kdePackages.ktorrent
  kdePackages.krita
  # ... more apps
];
```

### Mount Windows partition automatically
Add to `default.nix`:
```nix
fileSystems."/mnt/windows" = {
  device = "/dev/disk/by-uuid/YOUR-UUID";
  fsType = "ntfs-3g";
  options = [ "uid=1000" "gid=100" "umask=0002" "rw" ];
};
```

---

## Useful Resources

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Home Manager**: https://nix-community.github.io/home-manager/
- **KDE Plasma**: https://kde.org/plasma-desktop/
- **LACT**: https://github.com/ilya-zlobintsev/LACT
- **NixOS Search**: https://search.nixos.org/

---

## Support

If you encounter issues:

1. Check the troubleshooting sections in guides
2. Review NixOS logs: `journalctl -xe`
3. Ask on NixOS Discourse: https://discourse.nixos.org/
4. Join NixOS Discord: https://discord.gg/RbvHtGa

---

## Version Info

- **NixOS**: 25.05
- **State Version**: 25.05
- **Plasma**: 6.x
- **Home Manager**: Release 25.05

---

## Notes

- **Hardware config must be generated** on the actual machine
- **Fast Startup must be disabled** in Windows for proper dual boot
- **EFI partition is shared** between Windows and NixOS
- **GRUB is the bootloader**, installed by NixOS

---

Happy dual booting! 🐧🪟
