# Partition Layout for Dual Boot

## Visual Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                         /dev/nvme0n1                            │
│                      (Your main SSD/NVMe)                       │
└─────────────────────────────────────────────────────────────────┘
         │
         ├── /dev/nvme0n1p1 [EFI System Partition]
         │   Type: FAT32
         │   Size: ~100-500 MB
         │   Mount: /boot (in NixOS), /boot/efi (in some distros)
         │   ⚠️  SHARED between Windows and NixOS
         │   Contains: Windows Boot Manager + GRUB bootloader
         │
         ├── /dev/nvme0n1p2 [Microsoft Reserved]
         │   Type: Unknown
         │   Size: ~16 MB
         │   Mount: (none)
         │   ⚠️  Don't touch - Windows internal use
         │
         ├── /dev/nvme0n1p3 [Windows]
         │   Type: NTFS
         │   Size: Whatever remains after shrinking (e.g. 200 GB)
         │   Mount: C:\ (in Windows), /mnt/windows (optional in NixOS)
         │   Contains: Your Windows installation and files
         │
         ├── /dev/nvme0n1p4 [Windows Recovery]  (optional)
         │   Type: NTFS
         │   Size: ~500 MB - 1 GB
         │   ⚠️  Don't touch - Windows recovery
         │
         └── /dev/nvme0n1p5 [NixOS Root]  ← YOU CREATE THIS
             Type: ext4
             Size: 50-150 GB (whatever you freed up)
             Mount: / (in NixOS)
             Contains: Your NixOS system

Optional:
         └── /dev/nvme0n1p6 [NixOS Home]  ← OPTIONAL
             Type: ext4
             Size: Remaining space
             Mount: /home (in NixOS)
             Contains: Your personal files
```

---

## Before Shrinking (Windows only)

```
┌───────────────────────────────────────────────────────────┐
│  EFI   MSR      Windows (C:)              Recovery        │
│  500MB  16MB    [████████████████████████]  1GB           │
└───────────────────────────────────────────────────────────┘
```

---

## After Shrinking (Ready for NixOS)

```
┌───────────────────────────────────────────────────────────────────┐
│  EFI   MSR    Windows      Recovery    Unallocated Space          │
│  500MB  16MB  [█████████]   1GB        [     100 GB FREE    ]     │
└───────────────────────────────────────────────────────────────────┘
                                          ↑
                                          We'll install NixOS here
```

---

## After NixOS Installation (Dual Boot Complete)

```
┌────────────────────────────────────────────────────────────────────┐
│  EFI    MSR    Windows      Recovery       NixOS Root              │
│  500MB  16MB   [█████████]   1GB          [██████████]             │
│   ↑                                             ↑                   │
│   SHARED                                    ext4 Linux              │
│   Windows + GRUB                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Mount Points

### In Windows:
```
/dev/nvme0n1p1  →  (Hidden EFI partition)
/dev/nvme0n1p3  →  C:\
/dev/nvme0n1p5  →  (Not visible - Linux partition)
```

### In NixOS:
```
/dev/nvme0n1p1  →  /boot           (Shared EFI partition)
/dev/nvme0n1p3  →  /mnt/windows    (Optional - Windows files)
/dev/nvme0n1p5  →  /               (NixOS system)
/dev/nvme0n1p6  →  /home           (Optional - if separate home)
```

---

## Boot Process Flow

```
Power On
   ↓
UEFI Firmware
   ↓
Reads EFI Partition (/dev/nvme0n1p1)
   ↓
Finds: Windows Boot Manager + GRUB
   ↓
Boots: GRUB (NixOS installed it as default)
   ↓
GRUB Menu Shows:
   ├─→ NixOS (Default)
   └─→ Windows Boot Manager
       ↓
   User Selects
       ↓
   ┌───┴────┐
   │        │
NixOS    Windows
```

---

## Disk Space Recommendations

| Use Case | Windows | NixOS Root | NixOS Home (optional) |
|----------|---------|------------|----------------------|
| **Basic** | 200 GB | 50 GB | - |
| **Recommended** | 150 GB | 80 GB | 50 GB |
| **Power User** | 120 GB | 80 GB | Rest of disk |
| **Gaming Heavy** | 300 GB | 80 GB | 100 GB |

---

## Example Configurations

### Option 1: Simple (Single NixOS Partition)
```
EFI: 500 MB    (Shared)
Windows: 200 GB
NixOS: 100 GB  (Everything in /)
```

**Pros**: Simple, easy to manage
**Cons**: If system breaks, home files harder to recover

### Option 2: Separate Home (Recommended)
```
EFI: 500 MB       (Shared)
Windows: 150 GB
NixOS /: 50 GB    (System only)
NixOS /home: 100 GB  (Personal files)
```

**Pros**: Can reinstall system without losing personal files
**Cons**: Slightly more complex

### Option 3: Gaming Focus
```
EFI: 500 MB       (Shared)
Windows: 300 GB   (Big games)
NixOS /: 80 GB    (System + some games)
NixOS /home: 120 GB  (Personal files)
```

---

## Commands to Check Your Layout

```bash
# List all partitions with sizes
lsblk

# List with filesystem types and UUIDs
lsblk -f

# Detailed partition table
sudo fdisk -l

# Show mounted filesystems
mount | grep /dev/nvme

# Show disk usage
df -h
```

---

## Important Notes

1. **EFI Partition MUST be shared** - Both OSes boot from it
2. **Don't delete EFI partition** - You'll lose both OSes
3. **Partition numbers may vary** - Your nvme0n1p5 might be different
4. **Use `lsblk` to verify** - Always check before formatting
5. **UUIDs are unique** - Use them in fstab/hardware-configuration.nix

---

## What If I Have Multiple Drives?

If you have multiple physical drives (e.g., SSD + HDD):

### Option A: Separate Drives
```
/dev/nvme0n1 (SSD)
├─ EFI + Windows

/dev/sda (HDD or second SSD)
└─ NixOS
```

**Pros**: Clean separation, less risk
**Cons**: Must share EFI partition from nvme0n1

### Option B: Windows on Drive 1, NixOS on Drive 2
```
/dev/nvme0n1 (SSD 1)
├─ EFI (shared)
└─ Windows

/dev/nvme1n1 (SSD 2)
└─ NixOS (full disk)
```

**Note**: Still mount the EFI partition from nvme0n1 to /boot in NixOS

---

## Recovery Scenarios

### Lost GRUB (Can only boot Windows)
Boot NixOS USB and:
```bash
sudo mount /dev/nvme0n1p5 /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter
grub-install /dev/nvme0n1
exit
```

### Lost Windows Boot Manager
Boot Windows Recovery USB:
```
bootrec /fixmbr
bootrec /fixboot
bootrec /rebuildbcd
```
Then reinstall GRUB from NixOS USB (see above)

### Can't Boot Either OS
- Both bootloaders are on EFI partition
- Boot from USB
- Mount and reinstall bootloader
- Or restore EFI partition from backup
