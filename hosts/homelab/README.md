# Homelab NixOS Migration

Migrating the homelab server from Ubuntu 24.04 to NixOS 25.05.

## Hardware

| Component | Details |
|-----------|---------|
| CPU | AMD Ryzen 7 3700X (8-core) |
| RAM | 32GB |
| GPU | Intel Arc A310 (DG2) |
| Boot | BIOS/Legacy (not UEFI) |
| OS Disk | NVMe (nvme0n1) |
| Storage | RAID10 — 4x HDD (sda, sdb, sdc, sdd) → md0, ~7.5TB ext4 at /mnt/md0 |
| NIC | Realtek RTL8125 2.5GbE (eno1) |
| WiFi | Realtek RTL8852CE (unused, headless) |

## Services

- **Docker**: vaultwarden, nginx-proxy-manager, jellyfin, minecraft-server
- **NFS server**: /mnt/md0/data exported to 10.0.0.0/24
- **Samba**: [media] share at /mnt/md0, user: shareduser
- **Tailscale**: 100.66.232.121
- **SSH**: port 22, password + key auth
- **Cron**: minecraft backup every 30 min

## Network

- Static IP: 10.0.0.150/24
- Gateway: 10.0.0.1
- DNS: 1.1.1.1, 8.8.8.8

## Install Steps (from NixOS minimal ISO)

### 1. Connect to the network

```bash
# Check if ethernet auto-configured via DHCP
ip addr show

# If no IP, set one manually
sudo ip addr add 10.0.0.150/24 dev eno1
sudo ip link set eno1 up
sudo ip route add default via 10.0.0.1
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

### 2. Partition the NVMe

**WARNING: Only touch nvme0n1. Do NOT wipe sda, sdb, sdc, sdd — those are the RAID array.**

```bash
# Remove the old Ubuntu LVM layout first
sudo lvremove -f /dev/ubuntu-vg/ubuntu-lv
sudo vgremove -f ubuntu-vg
sudo pvremove /dev/nvme0n1p3

# Repartition
sudo parted /dev/nvme0n1 -- mklabel msdos
sudo parted /dev/nvme0n1 -- mkpart primary ext4 1MiB 512MiB
sudo parted /dev/nvme0n1 -- set 1 boot on
sudo parted /dev/nvme0n1 -- mkpart primary ext4 512MiB 100%

sudo mkfs.ext4 -L boot /dev/nvme0n1p1
sudo mkfs.ext4 -L nixos /dev/nvme0n1p2
```

### 3. Mount filesystems

```bash
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot
```

### 4. Generate hardware config

```bash
sudo nixos-generate-config --root /mnt
```

Review the output — verify it detects the NVMe partitions and RAID array:
```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```

### 5. Clone the flake and install

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"

nix-shell -p git

sudo git clone https://github.com/myles-coleman/nixos /mnt/etc/nixos/nixos

# Replace the placeholder hardware-configuration.nix with the real one
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/nixos/hosts/homelab/hardware-configuration.nix

# Review it
cat /mnt/etc/nixos/nixos/hosts/homelab/hardware-configuration.nix

# Install
sudo nixos-install --flake /mnt/etc/nixos/nixos#homelab
```

You will be prompted to set the **root password**.

### 6. Set user passwords

```bash
sudo nixos-enter --root /mnt -c "passwd bee"
sudo nixos-enter --root /mnt -c "passwd shareduser"
```

### 7. Reboot

```bash
sudo reboot
```

Remove the USB/ISO and boot from NVMe.

## Post-Install

### Move the repo

```bash
sudo mv /etc/nixos/nixos ~/nixos
sudo chown -R bee:users ~/nixos
```

### Set samba password

```bash
sudo smbpasswd -a shareduser
```

### Verify RAID array

```bash
cat /proc/mdstat
ls /mnt/md0
```

### Restore docker data

Copy backed-up docker data back to the appropriate locations, then:

```bash
# Copy docker-compose.yml to ~/
# Copy vaultwarden, nginx-proxy-manager, jellyfin, minecraft data

# Start services
cd ~ && docker compose up -d
```

### Verify services

```bash
# Check all services are running
systemctl status docker
systemctl status nfs-server
systemctl status samba-smbd
systemctl status tailscaled
systemctl status sshd

# Check NFS exports
showmount -e localhost

# Check samba shares
smbclient -L localhost -U shareduser

# Check docker containers
docker ps
```

### Auth to GitHub

```bash
nix-shell -p gh
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

### Commit the real hardware-configuration.nix

After verifying everything works:
```bash
cd ~/nixos
git add hosts/homelab/hardware-configuration.nix
git commit -m "feat: add real hardware-configuration.nix for homelab"
git push
```
