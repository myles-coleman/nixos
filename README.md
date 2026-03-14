# nixos

NixOS configurations for my machines, managed with flakes.

## Structure

```
├── flake.nix              # Entry point: defines each host
├── hosts/
│   ├── bee-pc/            # Desktop PC (AMD, no discrete GPU)
│   │   ├── default.nix
│   │   └── hardware-configuration.nix
│   └── bee-gpd/           # GPD handheld (AMD + NVIDIA)
│       ├── default.nix
│       └── hardware-configuration.nix
├── modules/
│   ├── common.nix         # User, shell, locale, base packages
│   ├── desktop.nix        # Hyprland, audio, bluetooth, fonts
│   ├── dev-tools.nix      # Docker, k8s, terraform, AWS
│   ├── gaming.nix         # Steam, gamemode, proton
│   ├── networking.nix     # Tailscale, Mullvad, NFS, mDNS
│   └── nvidia.nix         # NVIDIA drivers, Ollama w/ CUDA
└── rebuild.sh             # Build + commit script
```

## Usage

Rebuild the current machine (auto-detects hostname):
```bash
sudo nixos-rebuild switch --flake .
```

Or use the rebuild script:
```bash
sh ~/nixos/rebuild.sh
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

git config --global user.email "mylescoleman05@gmail.com"
git config --global user.name "Myles Coleman"
```

**Important:** The machine's hostname must match the flake configuration name (e.g. `bee-pc`, `bee-gpd`).
Set it in `hosts/<hostname>/default.nix` via `networking.hostName`.

To add a new machine:
1. Create `hosts/<hostname>/default.nix`
2. Copy `/etc/nixos/hardware-configuration.nix` into `hosts/<hostname>/`
3. Add a new entry in `flake.nix` under `nixosConfigurations`
4. Choose which modules to include

Note: If you want to eliminate the --impure flag in the future, you could:

Move the oh-my-posh theme into the repo instead of reading it from $HOME/dotfiles/
Vendor the krisp-patcher script as a local file instead of fetching it at eval time
But that's optional — --impure works fine for now.