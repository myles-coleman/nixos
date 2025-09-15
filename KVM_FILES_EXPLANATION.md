# KVM Module Files Explanation

## Core KVM Files

### 1. `kvm-module.nix` ✅ KEEP
- **Purpose**: NixOS configuration for KVM module support
- **Function**: Installs packages, kernel modules, and basic KVM setup
- **Status**: Essential for KVM functionality

### 2. `kvm-switch.sh` ✅ KEEP
- **Purpose**: Main script to toggle KVM mode on/off
- **Function**: Starts/stops video display from HDMI capture device
- **Usage**: Run directly or bind to a key

### 3. `kvm-escape.sh` ✅ KEEP
- **Purpose**: Emergency escape from KVM mode
- **Function**: Kills all KVM-related processes
- **Status**: Useful failsafe

## Automation Files

### 4. `kvm-auto-detect.sh` ✅ KEEP
- **Purpose**: Auto-detect HDMI connection and start KVM
- **Function**: Monitors for KVM hardware and starts everything automatically
- **Usage**: Can run as service or manually
- **Benefit**: No manual intervention needed

### 5. `kvm-auto-start.nix` ✅ KEEP
- **Purpose**: NixOS configuration for systemd services
- **Function**: Defines service for auto-detect
- **Usage**: Import in configuration.nix
- **Status**: Proper way to configure services in NixOS

## How to Use

### Method 1: Manual Toggle (Waybar Button)
Click the KVM button in your waybar or run:
```bash
/home/bee/nixos/kvm-switch.sh
```

### Method 2: Auto-Detection
1. Enable in kvm-auto-start.nix (uncomment wantedBy)
2. KVM starts automatically when HDMI is connected

## Quick Commands

```bash
# Start KVM manually
/home/bee/nixos/kvm-switch.sh

# Start auto-detection
/home/bee/nixos/kvm-auto-detect.sh start

# Emergency stop
/home/bee/nixos/kvm-escape.sh
```

## NixOS Integration

Add to your `configuration.nix`:
```nix
imports = [
  ./kvm-module.nix          # Basic KVM support
  ./kvm-auto-start.nix      # Systemd services
];
```

Then rebuild:
```bash
sudo nixos-rebuild switch
```

## Waybar Integration

The waybar configuration includes a custom KVM button that:
- Shows KVM status (green when active)
- Left-click: Toggle KVM mode
- Right-click: Emergency stop

## Files Summary

- `kvm-module.nix` - Core NixOS configuration
- `kvm-switch.sh` - Main toggle script
- `kvm-escape.sh` - Emergency stop
- `kvm-auto-detect.sh` - Auto-detection daemon
- `kvm-auto-start.nix` - Systemd service configuration
