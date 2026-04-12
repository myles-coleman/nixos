# PiKVM on NixOS — Setup Guide

## Overview

PiKVM running on a Raspberry Pi 4 with NixOS. Provides remote KVM (keyboard, video, mouse)
access to a target machine via a web browser. Uses the TC358743 CSI-2 HDMI capture bridge,
USB OTG for HID emulation, and GPIO for ATX power control.

**Status: Fully operational.** All core services running — kvmd, nginx, Janus WebRTC,
OTG gadget, EDID loader, and MSD virtual drive.

---

## Architecture

```
Target PC ──HDMI──► TC358743 CSI-2 ──ribbon──► Pi 4 (10.0.0.175)
Target PC ◄──USB-C OTG (keyboard/mouse)──────── Pi 4
Target PC ◄──GPIO (ATX power/reset)──────────── Pi 4 (optional)

Browser ──HTTP──► Pi 4 nginx:8080 ──► kvmd (web UI + API)
                                  ──► ustreamer (MJPEG/H.264 video)
                                  ──► janus (WebRTC low-latency video)
```

---

## Research & Sources

### Primary reference: `nixkvm` wip branch
- **URL**: https://github.com/MatthewCroughan/nixkvm/tree/wip
- Packages: `kvmd` v4.2, `ustreamer` v6.12, patched `janus-gateway`, `pyghmi`
- NixOS modules for kvmd, kvmd-otg, kvmd-janus, kvmd-edid-loader, nginx proxy
- **kvmd v4.2** used as the known-working version (latest is v4.163, large gap)

### Other references
- [nixpkgs issue #428203](https://github.com/nixos/nixpkgs/issues/428203) — packaging request for kvmd
- [pikvm/ustreamer PR #136](https://github.com/pikvm/ustreamer/pull/136) — Nix flake for ustreamer (never merged)
- [pikvm/pikvm issue #1382](https://github.com/pikvm/pikvm/issues/1382) — test failures when packaging for Nix

### Key technical discoveries

**RPi downstream kernel required for CSI-2:**
The mainline Linux kernel's `unicam` driver has different DT bindings than the RPi downstream
kernel's `bcm2835-unicam`. The Pi firmware's `tc358743.dtbo` overlay targets the downstream
driver. Using `linuxPackages_rpi4` (kernel 6.6.51) resolves this.
- Reference: https://www.raspberrypi.com/documentation/computers/linux_kernel.html

**Device tree overlays via Pi firmware, not U-Boot:**
NixOS uses U-Boot + extlinux on aarch64. U-Boot loads its own DTB via `FDTDIR` in
`extlinux.conf`, ignoring the firmware-modified DTB (which has overlays applied).
Fix: set `hardware.deviceTree.enable = false` so extlinux omits `FDTDIR`, and the
Pi firmware's DTB (with `dtoverlay=tc358743` and `dtoverlay=dwc2` from `config.txt`)
passes through to the kernel.
- Reference: https://nixos.wiki/wiki/NixOS_on_ARM/Raspberry_Pi_4
- Reference: https://www.raspberrypi.com/documentation/computers/config_txt.html

**initrd module conflicts with RPi kernel:**
NixOS `all-hardware.nix` adds Allwinner/Rockchip modules (`sun4i-drm`, etc.) for all
aarch64 platforms. These don't exist in the RPi downstream kernel. Fix: `lib.mkForce`
on `boot.initrd.availableKernelModules` with only RPi-relevant modules.

**kvmd fstab parsing for MSD:**
kvmd's `fstab.py` scans `/etc/fstab` for mount options matching
`X-kvmd.otgmsd-root=<path>` and `X-kvmd.otgmsd-user=<user>`. A loopback vfat
image mounted with these options satisfies the requirement.

---

## File Structure

```
flake.nix                              # pikvm host (aarch64-linux, no commonModules)
modules/pikvm.nix                      # NixOS module: inline derivations + services
config/pikvm/
  main.yaml                            # kvmd config (HID, ATX, MSD, streamer)
  logging.yaml                         # kvmd logging config
  meta.yaml                            # kvmd metadata
hosts/pikvm/
  default.nix                          # Host config (boot, network, users)
  hardware-configuration.nix           # SD image + firmware partition setup
  SETUP.md                             # This file
```

### `modules/pikvm.nix`

Inline derivations for `kvmd` v4.2, `ustreamer` v6.12, and `pyghmi` v1.5.69.
No external `packages/` directory — follows repo conventions.

**`services.pikvm` options:**
| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable PiKVM services |
| `hostname` | `"pikvm"` | Hostname in web UI |
| `videoDevice` | `"/dev/kvmd-video"` | HDMI capture device path |
| `listenPort` | `443` | Nginx listen port |
| `enableJanus` | `true` | WebRTC gateway |
| `enableVNC` | `false` | VNC proxy |
| `enableIPMI` | `false` | IPMI proxy |
| `enableOTGNet` | `false` | Ethernet over USB |
| `enableWatchdog` | `false` | Hardware watchdog |

**Sets up:** systemd services (kvmd, kvmd-otg, kvmd-edid-loader, kvmd-janus, kvmd-msd-image),
users/groups (kvmd, gpio), nginx reverse proxy, kernel modules (dwc2, libcomposite, tc358743,
bcm2835-unicam), udev rules (video, GPIO, HID), MSD loopback image, tmpfiles, firewall, sudo.

### `hosts/pikvm/default.nix`

- **Kernel:** `linuxPackages_rpi4` (RPi downstream, 6.6.51)
- **Boot:** extlinux, no FDTDIR (firmware handles DT overlays)
- **Network:** static IP `10.0.0.175/24`, gateway `10.0.0.1`
- **PiKVM:** port 8080, Janus enabled, VNC/IPMI disabled
- **SSH:** key-only auth + Tailscale
- **User:** `bee` with wheel/video/gpio, passwordless sudo
- **Swap:** zram 50%, zstd

### `hosts/pikvm/hardware-configuration.nix`

Custom `sdImage.populateFirmwareCommands` using `lib.mkForce` to override
`sd-image-aarch64.nix` defaults. Creates a `config.txt` with:
- `dtoverlay=tc358743` (CSI-2 HDMI capture)
- `dtoverlay=dwc2,dr_mode=peripheral` (USB OTG)

Copies `.dtbo` overlay files from `pkgs.raspberrypifw` to the firmware partition.

---

## Usage

### Build the SD image
```bash
nix build .#nixosConfigurations.pikvm.config.system.build.sdImage
```
Requires binfmt on the build host: `boot.binfmt.emulatedSystems = ["aarch64-linux"]`.

### Flash the SD card
```bash
sudo dd if=result/sd-image/nixos-sd-image-*.img of=/dev/sdX bs=4M status=progress
```

### First boot
1. Insert SD card, connect ethernet, power on
2. SSH in: `ssh bee@10.0.0.175`
3. Create a kvmd web UI user:
   ```bash
   sudo kvmd-htpasswd set admin
   ```
4. Access web UI: `http://10.0.0.175:8080`

### Remote rebuilds
```bash
./rebuild.sh --pikvm          # build locally, deploy to Pi
./rebuild.sh --pikvm --force  # skip dirty check
```

### Remote access via Tailscale
```bash
ssh bee@10.0.0.175 "sudo tailscale up"
```
Then access via `http://<tailscale-ip>:8080` from anywhere.

---

## Hardware

| Component | Description |
|-----------|-------------|
| **Raspberry Pi 4** | Any RAM variant |
| **TC358743 CSI-2 board** | HDMI capture via camera ribbon cable |
| **USB-C OTG cable** | Pi USB-C to target USB-A for HID |
| **Ethernet** | Wired connection (static IP) |
| **ATX GPIO wires** | Optional: power/reset control via GPIO |

---

## Services & Systemd Units

| Service | Status | Purpose |
|---------|--------|---------|
| `kvmd` | active (running) | Main PiKVM daemon (web UI, API, HID, ATX, MSD) |
| `kvmd-otg` | active (exited) | USB OTG gadget setup (keyboard/mouse/storage) |
| `kvmd-edid-loader` | active (exited) | Loads EDID onto TC358743 capture chip |
| `kvmd-janus` | active (running) | Janus WebRTC gateway for H.264 streaming |
| `kvmd-msd-image` | active (exited) | Creates/mounts 256MB vfat loopback for MSD |
| `nginx` | active (running) | Reverse proxy on port 8080 |

---

## Udev Rules

| Match | Symlink/Action |
|-------|---------------|
| `ATTR{name}=="unicam-image"` | `/dev/kvmd-video` |
| `KERNEL=="gpiochip*"` | `GROUP="gpio", MODE="0660"` |
| `KERNEL=="hidg0"` | `/dev/kvmd-hid-keyboard`, `GROUP="kvmd"` |
| `KERNEL=="hidg1"` | `/dev/kvmd-hid-mouse`, `GROUP="kvmd"` |

---

## Known Issues

- **kvmd v4.2 is old** — latest is v4.163. May need version bump eventually.
- **Tests disabled** (`doCheck = false`) — kvmd tests require `/etc/kvmd/main.yaml` at parse time.
- **`vcgencmd get_throttled`** — logs a harmless parse error (firmware tool output mismatch).
- **`kvmd-fan` not found** — cosmetic error, no fan service configured (no fan attached).
- **janus-gateway patches** — `refcount.h` copied into plugins dir; may break with newer janus.
- **SD image rebuild required** for kernel or firmware changes (boot partition is read-only).
- **`initialPassword` removed** — set password via `passwd` on the Pi or use SSH keys only.

---

## Troubleshooting

### Capture device not detected
```bash
# Check DT overlay applied
sudo dmesg | grep -i tc358
# Should show: tc358743 10-000f: tc358743 found @ 0x1e

# Check unicam driver
lsmod | grep unicam
# Should show: bcm2835_unicam

# Check video device
v4l2-ctl --list-devices
# Should show: unicam (platform:fe801000.csi) -> /dev/video0
```

### kvmd won't start
```bash
sudo journalctl -u kvmd -n 30 --no-pager
# Common causes: missing /etc/kvmd/totp.secret, GPIO permissions, MSD mount
```

### Remote rebuild fails
```bash
cat ~/nixos/nixos-switch.log  # full build output
```

### Reflash needed after kernel change
Kernel or firmware partition changes require a new SD image:
```bash
nix build .#nixosConfigurations.pikvm.config.system.build.sdImage
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
```
