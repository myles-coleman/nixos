# nixos

NixOS configurations for my machines, managed with home-manager and flakes.

## Structure

```
├── flake.nix              # Entry point: defines each host
├── hosts/
│   ├── bee-pc/            # Desktop PC (AMD, no discrete GPU)
│   │   ├── default.nix
│   │   ├── hardware-configuration.nix
│   │   └── home/          # PC-specific dotfiles
│   │       ├── default.nix
│   │       ├── hyprland.conf
│   │       └── start.sh
│   ├── bee-gpd/           # GPD handheld (AMD + NVIDIA)
│   │   ├── default.nix
│   │   ├── hardware-configuration.nix
│   │   └── home/          # GPD-specific dotfiles
│   │       ├── default.nix
│   │       ├── hyprland.conf
│   │       └── start.sh
│   ├── homelab/           # Server (Docker, NFS, Samba, Intel Arc)
│   │   ├── default.nix
│   │   ├── hardware-configuration.nix
│   │   └── home/          # Homelab home-manager config
│   └── pikvm/             # Raspberry Pi 4 KVM (aarch64-linux)
│       ├── default.nix
│       ├── hardware-configuration.nix
│       └── SETUP.md       # PiKVM setup guide
├── modules/
│   ├── common.nix         # User, shell, locale, base packages
│   ├── desktop.nix        # Hyprland, audio, bluetooth, fonts
│   ├── dev-tools.nix      # Docker, k8s, terraform, AWS
│   ├── gaming.nix         # Steam, gamemode, proton
│   ├── home.nix           # Shared home-manager config
│   ├── networking.nix     # Tailscale, Mullvad, NFS, mDNS
│   ├── nvidia.nix         # NVIDIA drivers, Ollama w/ CUDA
│   └── pikvm.nix          # PiKVM module (kvmd, ustreamer, Janus)
├── config/                # Vendored configs and dotfiles
│   ├── mangohud/          # MangoHud configs
│   ├── pikvm/             # PiKVM YAML configs (main, logging, meta)
│   ├── rofi/              # Rofi theme
│   ├── waybar/            # Waybar config, styles, and KVM switch script
│   ├── krisp-patcher.py
│   ├── oh-my-posh-theme.json
│   └── wallpaper1.jpg
└── rebuild.sh             # Build + commit script
```

## Usage

Rebuild the current machine (auto-detects hostname):
```bash
rebuild
```

Deploy to the homelab remotely (builds locally, deploys to `bee@10.0.0.150` via SSH):
```bash
rebuild --homelab
```

Deploy to the pikvm remotely (cross-compiles aarch64, deploys to `bee@10.0.0.175` via SSH):
```bash
rebuild --pikvm
```

Dry run (build without switching):
```bash
rebuild --dry-run
```

Force rebuild even if no `.nix`/`flake.lock` changes detected:
```bash
rebuild --force
```

Update flake inputs:
```bash
nix flake update
```

The rebuild script auto-formats with `alejandra`, skips if no changes are detected (unless `--force`), and auto-commits on success with the NixOS generation metadata as the commit message.

## New Devices

Locally auth to github and clone the repo:
```bash
nix-shell -p gh
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
gh repo clone https://github.com/myles-coleman/nixos
```

**Important:** The machine's hostname must match the flake configuration name (e.g. `bee-pc`, `bee-gpd`).
Set it in `hosts/<hostname>/default.nix` via `networking.hostName`.

To add a new machine:
1. Create `hosts/<hostname>/default.nix`
2. Copy `/etc/nixos/hardware-configuration.nix` into `hosts/<hostname>/`
3. Create `hosts/<hostname>/home/default.nix` for host-specific dotfiles
4. Add a new entry in `flake.nix` under `nixosConfigurations`
5. Choose which modules to include

## Dotfiles

Dotfiles are managed by [home-manager](https://github.com/nix-community/home-manager) instead of a separate repo.
This replaces the old `dotfiles` repo which used per-machine branches.
Shared dotfiles (kitty, rofi, mangohud, waybar, oh-my-posh) live in `modules/home.nix`.
Anything that differs between machines (e.g. hyprland.conf, start.sh) goes in the host's `home/` directory.

## AI Artifacts

SDD specs and research notes for this repo live in the private AI artifacts vault: `~/ai-artifacts-vault/nixos/docs/` (https://github.com/myles-coleman/ai-artifacts-vault).
