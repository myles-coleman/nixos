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
│   ├── homelab/           # Server (Docker, NFS, Samba, Intel Arc); aspect pilot
│   │   ├── default.nix    # Host aspect: lists shared aspects + host-local imports
│   │   └── hardware-configuration.nix
│   ├── pikvm/             # Raspberry Pi 4 KVM (aarch64-linux)
│   │   ├── default.nix
│   │   ├── hardware-configuration.nix
│   │   └── SETUP.md       # PiKVM setup guide
│   ├── node0/             # k3s control plane (aarch64, NVMe)
│   ├── node1/ … node3/    # k3s agents (aarch64, NVMe)
│   ├── node4/             # k3s agent (aarch64, SD card)
│   └── rpi3/              # Chromium kiosk (aarch64, SD card)
├── modules/
│   ├── aspects/           # flake-parts aspect registry (see aspects/README.md)
│   ├── common.nix         # User, shell, locale, base packages
│   ├── desktop.nix        # Hyprland, audio, bluetooth, fonts
│   ├── dev-tools.nix      # Docker, k8s, terraform, AWS
│   ├── gaming.nix         # Steam, gamemode, proton
│   ├── home.nix           # Shared home-manager config
│   ├── networking.nix     # Tailscale, Mullvad, NFS, mDNS
│   ├── nvidia.nix         # NVIDIA drivers, Ollama w/ CUDA
│   ├── pikvm.nix          # PiKVM module (kvmd, ustreamer, Janus)
│   ├── sops.nix           # sops-nix per-host key path wiring
│   ├── steam-remote-play-client.nix  # Steam remote-play client
│   └── rpi/               # RPi fleet modules (base, k3s-*, k3s-token-sops, node-health, disko)
├── config/                # Vendored configs and dotfiles
│   ├── mangohud/          # MangoHud configs
│   ├── pikvm/             # PiKVM YAML configs (main, logging, meta)
│   ├── rofi/              # Rofi theme
│   ├── waybar/            # Waybar config, styles, and KVM switch script
│   ├── krisp-patcher.py
│   ├── oh-my-posh-theme.json
│   └── wallpaper1.jpg
└── rebuild.sh             # Build script (formats, builds/switches; does not commit)
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

The rebuild script auto-formats with `alejandra`, skips if no changes are detected (unless `--force`), and builds/switches locally. It no longer commits or pushes: changes go through a branch and pull request so CI can verify and deploy them.

## Deployment (CI)

Changes reach the fleet through GitHub Actions, not `rebuild.sh`:

- **Pull requests** build every in-scope host (`ubuntu-24.04` for x86_64, `ubuntu-24.04-arm` for `pikvm` and the RPi fleet), post a per-host closure diff, and enforce the `nixpkgs` pin-alignment guard.
- **Merges to `main`** deploy the auto-deploy set (`homelab`, `bee-gpu-server`) with `deploy-rs` (magic rollback enabled) behind the protected `production` GitHub Environment; a host is activated only when its built toplevel differs from what it is already running. `protecli-vault`, `pikvm`, and the RPi hosts (`node0`–`node4`, `rpi3`) are manual (`workflow_dispatch`) only; `bee-pc`/`bee-gpd` never auto-deploy.
- `main` is protected: pull requests and required checks are mandatory, and force-pushes are blocked.

Deploy tooling is `deploy-rs` (pinned in `flake.nix`). Run it locally with `nix run .#deploy -- .#<host> --skip-checks -- -L`. The `--skip-checks` flag is required locally: without it, deploy-rs's pre-build check builds every node's activation, including `pikvm`'s aarch64 `linux-rpi` kernel, which cannot build on an x86_64 host. Validate the deploy schema separately with `nix flake check --no-build`.

The RPi hosts are manual-only. Deploy one from CI with a `workflow_dispatch` run, or locally:

```bash
# k3s node over the LAN (sshUser `pi`)
nix run .#deploy -- .#node1 --skip-checks -- -L
# rpi3 kiosk over the LAN (sshUser `bee`)
nix run .#deploy -- .#rpi3 --skip-checks -- -L
```

These targets resolve only when CI (or your machine) can reach the LAN via `protecli-vault`'s advertised subnet routes.

## k3s cluster (node0–node4)

The five-node Raspberry Pi 5 k3s cluster is imported from the former `rpi5-nixos`
repository (program Phase 4). `node0` is the control plane, `node1`–`node3` are NVMe
agents, and `node4` is an SD-card agent. They build with the `nixos-raspberrypi`
vendor modules and use `disko` for NVMe partitioning. The cluster join token is
supplied at activation by `sops-nix` (`k3s_server_token` in `secrets/common.yaml`);
it is never written into the Nix store or the SD images.

Before a node's first activation under the monorepo, provision its per-host age key
out-of-band (the deploy identity is `pi`):

```bash
scripts/provision-host-key.sh 10.0.0.140 pi
```

## rpi3 kiosk

The `rpi3` Chromium kiosk is imported from the former `rpi3-nixos` repository
(program Phase 4). It builds on the `nixos-raspberrypi` `raspberry-pi-3` board and
SD-image modules, replacing `nixos-hardware` and the hand-rolled firmware-config
oneshot with declarative `hardware.raspberry-pi.config`. The kiosk launches
`greetd` → `cage` → Chromium in kiosk mode as user `bee`.

SSH password authentication remains enabled on `rpi3` (preserved from the source
config, and a follow-up hardening item); the old `rpi3-nixos` `AGENTS.md` claimed
key-only access, which was inaccurate. Provision its age key before first
activation with the `bee` deploy identity. `rpi3` holds a static LAN address of
`10.0.0.145` (configured via a declarative NetworkManager profile):

```bash
scripts/provision-host-key.sh 10.0.0.145 bee
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
