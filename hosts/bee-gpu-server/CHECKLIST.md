# Pre-Installation Checklist

Use this checklist to ensure you're ready for dual boot installation.

---

## Phase 1: Windows Preparation

### Backups
- [ ] Important files backed up to external drive/cloud
- [ ] Windows product key saved (if OEM, it's in BIOS)
- [ ] List of installed software you need
- [ ] Browser bookmarks exported (if not synced)

### BIOS/UEFI Settings
- [ ] Secure Boot disabled in BIOS
- [ ] Boot mode set to UEFI (not Legacy/CSM)
- [ ] Virtualization enabled (AMD-V for Ryzen)
- [ ] Know your BIOS key (usually DEL or F2)
- [ ] Know your Boot Menu key (usually F12)

### Windows Configuration
- [ ] Fast Startup disabled:
  - Control Panel → Power Options → Choose what power buttons do
  - Uncheck "Turn on fast startup (recommended)"
- [ ] Windows fully updated (Windows Update)
- [ ] Disk checked for errors (chkdsk)
- [ ] Disk defragmented (if HDD, not needed for SSD)

### Disk Space
- [ ] At least 100 GB free space available
- [ ] Windows partition shrunk using Disk Management
- [ ] Unallocated space visible in Disk Management
- [ ] Screenshot of Disk Management for reference

---

## Phase 2: Installation Media

### NixOS ISO
- [ ] Downloaded NixOS 25.05 or newer
- [ ] ISO verified (checksum if paranoid)
- [ ] USB drive prepared (8GB minimum)
- [ ] Bootable USB created with Rufus (Windows) or dd (Linux)
- [ ] USB boot mode: GPT + UEFI

### Repository Access
- [ ] Your nixos config repo pushed to GitHub/GitLab
- [ ] OR nixos repo on a separate USB drive
- [ ] OR know how to set up minimal install first
- [ ] WiFi password handy (if using WiFi)

---

## Phase 3: Hardware Information

### Collect This Info
- [ ] Disk name: _________________ (e.g., /dev/nvme0n1)
- [ ] EFI partition: _____________ (e.g., /dev/nvme0n1p1)
- [ ] Windows partition: _________ (e.g., /dev/nvme0n1p3)
- [ ] Free space location: _______ (e.g., /dev/nvme0n1p5)
- [ ] Total disk size: ___________ (e.g., 500 GB)
- [ ] Free space size: ___________ (e.g., 100 GB)

### System Specs (for reference)
- [x] CPU: AMD Ryzen 5 5600X
- [x] GPU: AMD Radeon RX 7900 XTX
- [x] RAM: 24 GB
- [ ] Motherboard: _________________
- [ ] Disk type: NVMe / SATA SSD / HDD

---

## Phase 4: Knowledge Check

### Do You Know How To:
- [ ] Boot into BIOS/UEFI (DEL or F2 during startup)
- [ ] Access Boot Menu (F12 during startup)
- [ ] Use basic Linux commands (ls, cd, mount)
- [ ] Recover if something goes wrong

### Have You Read:
- [ ] DUAL_BOOT_GUIDE.md (detailed instructions)
- [ ] PARTITION_LAYOUT.md (understand disk layout)
- [ ] QUICK_START.md (fast reference)
- [ ] This checklist completely

---

## Phase 5: Safety Checks

### Before You Start
- [ ] Computer is plugged in (not on battery)
- [ ] No important work unsaved
- [ ] Enough time (1-2 hours for installation)
- [ ] Stable internet connection (for downloads)
- [ ] Know where Windows Recovery USB is (just in case)

### Do NOT Proceed If:
- [ ] ❌ You haven't backed up important data
- [ ] ❌ You don't have Windows recovery media
- [ ] ❌ You're not sure which disk to install on
- [ ] ❌ You haven't disabled Fast Startup
- [ ] ❌ Secure Boot is still enabled

---

## Phase 6: Day of Installation

### Morning of Install
- [ ] Good night's sleep (don't rush)
- [ ] Read through guide one more time
- [ ] USB drive ready
- [ ] Computer plugged in
- [ ] Phone/tablet handy (to read guide while installing)

### Items Nearby
- [ ] This printed guide (or on another device)
- [ ] Phone with internet (for troubleshooting)
- [ ] Notepad for writing down info
- [ ] External backup drive (for peace of mind)

---

## During Installation

### Remember To:
- [ ] Take your time
- [ ] Read each step carefully
- [ ] Verify commands before running
- [ ] Check partition names with `lsblk` before formatting
- [ ] Don't skip the hardware-configuration.nix step

### Common Mistakes to Avoid:
- [ ] ❌ Formatting wrong partition
- [ ] ❌ Not mounting EFI partition
- [ ] ❌ Forgetting to set user password
- [ ] ❌ Not copying hardware-configuration.nix
- [ ] ❌ Rebooting before installation completes

---

## Post-Installation

### First Boot Checks
- [ ] GRUB menu appears
- [ ] Both NixOS and Windows options visible
- [ ] NixOS boots successfully
- [ ] Can log in as 'bee'
- [ ] Plasma desktop loads
- [ ] Network works

### Verify Dual Boot
- [ ] Reboot and select Windows from GRUB
- [ ] Windows boots successfully
- [ ] Windows still works normally
- [ ] Reboot back to NixOS
- [ ] Both OSes are working

### Configuration
- [ ] Copy hardware-configuration.nix to repo
- [ ] Commit changes to git
- [ ] Test `rebuild` command
- [ ] Configure any additional settings
- [ ] Set up Windows partition mount (optional)

---

## Emergency Contacts

### If Something Goes Wrong:

**Can't boot anything:**
- Boot from Windows Recovery USB
- Or boot from NixOS USB
- Follow recovery steps in DUAL_BOOT_GUIDE.md

**Need help:**
- NixOS Discord: https://discord.gg/RbvHtGa
- NixOS Discourse: https://discourse.nixos.org/
- r/NixOS on Reddit

**Your backup plan:**
- Windows Recovery USB location: _________________
- Backup drive location: _________________
- Time machine/backup software: _________________

---

## Final Reminder

✅ **You're Ready If:**
- All boxes above are checked
- You've read the guides
- You have backups
- You understand the risks

⚠️ **Stop If:**
- Missing backups
- Unsure about any step
- Time pressure
- Uncertain about which disk to use

---

## Estimated Time

- Reading guides: 30 minutes
- Windows preparation: 15 minutes
- Creating USB: 10 minutes
- NixOS installation: 30-60 minutes
- Testing and verification: 15 minutes

**Total: 1.5 - 2.5 hours**

---

## Go/No-Go Decision

I am ready to proceed because:
- [ ] I have backed up all important data
- [ ] I understand the dual boot process
- [ ] I have read the installation guides
- [ ] I have all necessary materials
- [ ] I have enough time
- [ ] I accept the risks

**Signature/Date**: ________________

---

Good luck! Remember: Take your time and read carefully. 🚀
