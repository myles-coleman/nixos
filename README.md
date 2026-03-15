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
│   └── bee-gpd/           # GPD handheld (AMD + NVIDIA)
│       ├── default.nix
│       ├── hardware-configuration.nix
│       └── home/          # GPD-specific dotfiles
│           ├── default.nix
│           ├── hyprland.conf
│           └── start.sh
├── modules/
│   ├── common.nix         # User, shell, locale, base packages
│   ├── desktop.nix        # Hyprland, audio, bluetooth, fonts
│   ├── dev-tools.nix      # Docker, k8s, terraform, AWS
│   ├── gaming.nix         # Steam, gamemode, proton
│   ├── home.nix           # Shared home-manager config
│   ├── networking.nix     # Tailscale, Mullvad, NFS, mDNS
│   └── nvidia.nix         # NVIDIA drivers, Ollama w/ CUDA
├── config/                # Vendored configs and dotfiles
│   ├── mangohud/          # MangoHud configs
│   ├── rofi/              # Rofi theme
│   ├── waybar/            # Waybar config, styles, and scripts
│   ├── krisp-patcher.py
│   └── oh-my-posh-theme.json
└── rebuild.sh             # Build + commit script
```

## Usage

Rebuild the current machine (auto-detects hostname):
```bash
sudo nixos-rebuild switch --flake .
```

Or use the rebuild alias:
```bash
rebuild
```

Update flake inputs:
```bash
nix flake update
```

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
3. Create `hosts/<hostname>/home.nix` for host-specific dotfiles
4. Add a new entry in `flake.nix` under `nixosConfigurations`
5. Choose which modules to include

## Dotfiles

Dotfiles are managed by [home-manager](https://github.com/nix-community/home-manager) instead of a separate repo.
This replaces the old `dotfiles` repo which used per-machine branches.

| Before (dotfiles repo branches) | After (this repo)                                    |
|---------------------------------|------------------------------------------------------|
| `master` branch → bee-pc        | `hosts/bee-pc/home/` + host-specific config files    |
| `gpd-pocket` branch → bee-gpd   | `hosts/bee-gpd/home/` + host-specific config files   |
| Shared configs duplicated        | `modules/home.nix` (common to both)                  |

Shared dotfiles (kitty, rofi, mangohud, waybar, oh-my-posh) live in `modules/home.nix`.
Anything that differs between machines (e.g. hyprland.conf, start.sh) goes in the host's `home/` directory.

### Migrating an existing machine

After pulling the home-manager changes and running `rebuild` for the first time, home-manager will
back up any existing dotfiles it needs to manage (e.g. files placed by stow) with a `.backup` suffix.

Clean up the backup files and remove stow symlinks:
```bash
# Remove all .backup files created by home-manager
rm ~/.config/hypr/*.backup 2>/dev/null
rm ~/.config/waybar/*.backup 2>/dev/null
rm ~/.config/kitty/*.backup 2>/dev/null
rm ~/.config/rofi/*.backup 2>/dev/null
rm ~/.config/MangoHud/*.backup 2>/dev/null
rm ~/.config/oh-my-posh/*.backup 2>/dev/null

# Remove any leftover stow-managed files not covered by home-manager
rm -f ~/.config/waybar/kvm-switch.sh  # only needed on bee-gpd, managed there

# Unstow all packages from the old dotfiles repo
cd ~/dotfiles && stow -D */

# Verify dotfiles are now nix store symlinks
ls -la ~/.config/hypr/hyprland.conf  # should point to /nix/store/...
```

Once verified, the `dotfiles` repo is no longer needed on this machine.
