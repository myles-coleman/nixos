# NixOS K3s Cluster Deployment

## Overview

Deploy NixOS with k3s to Raspberry Pi 5 nodes using installer SD card first.

## Prerequisites

- Raspberry Pi 5 with SSD
- SD card for installer
- Network access to Pi
- K3s token configured

## Quick Start

### 1. Generate K3s Token

```bash
openssl rand -hex 32 > secrets/token
```

### 2. Build Installer Image

```bash
nix build github:nvmd/nixos-raspberrypi#installerImages.rpi5
zstd -d ./result/sd-image/*.img.zst -c | sudo dd of=/dev/sdX bs=4M status=progress
```

### 3. Boot from Installer

1. Insert SD card into Pi
2. Boot and note SSH credentials from screen
3. SSH in: `ssh root@nixos-installer.local`
4. Check SSD device: `lsblk`

### 4. Deploy

```bash
nixos-anywhere --flake .#node1 root@nixos-installer.local
```

## Updates

### Update single node
```bash
nixos-rebuild switch --flake .#node1 --target-host pi@node1.local --use-remote-sudo --build-host pi@node1.local
```

### Update all nodes
```bash
for i in {0..3}; do
  nixos-rebuild switch --flake .#node$i --target-host pi@node$i.local --use-remote-sudo --build-host pi@node$i.local
done
```

### Rotate k3s token
```bash
# Generate new token
openssl rand -hex 32 > secrets/token

# Rebuild all nodes
nix build .#node0 .#node1 .#node2 .#node3
```
