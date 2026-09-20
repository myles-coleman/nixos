#!/usr/bin/env bash

# A rebuild script that commits on a successful build
set -e

HOMELAB_HOST="bee@10.0.0.150"
PIKVM_HOST="bee@10.0.0.175"
BEE_GPU_SERVER_HOST="bee@10.0.0.156"
PROTECLI_VAULT_HOST="bee@100.112.185.27"
HOMELAB=false
PIKVM=false
BEE_GPU_SERVER=false
PROTECLI_VAULT=false
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --homelab) HOMELAB=true ;;
        --pikvm) PIKVM=true ;;
        --bee-gpu-server) BEE_GPU_SERVER=true ;;
        --protecli-vault) PROTECLI_VAULT=true ;;
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
    esac
done

# cd to your config dir
pushd ~/nixos/

# Early return if no changes were detected (skip with --force)
if ! $FORCE && git diff --quiet -- '**/*.nix' 'flake.lock'; then
    echo "No changes detected, exiting."
    popd
    exit 0
fi

# Autoformat your nix files
alejandra . &>/dev/null \
  || ( alejandra . ; echo "formatting failed!" && exit 1)

# Shows your changes
git diff -U0 -- '**/*.nix' 'flake.lock'

ACTION="switch"
if $DRY_RUN; then
    ACTION="dry-build"
    echo "NixOS Dry Run..."
else
    echo "NixOS Rebuilding..."
fi

if $HOMELAB; then
    # Build locally, deploy to homelab
    nixos-rebuild "$ACTION" --flake .#homelab \
        --target-host "$HOMELAB_HOST" \
        --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
elif $PIKVM; then
    # Build locally (cross-compile aarch64), deploy to pikvm
    nixos-rebuild "$ACTION" --flake .#pikvm \
        --target-host "$PIKVM_HOST" \
        --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
elif $BEE_GPU_SERVER; then
    # Build locally, deploy to bee-gpu-server
    nixos-rebuild "$ACTION" --flake .#bee-gpu-server \
        --target-host "$BEE_GPU_SERVER_HOST" \
        --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
elif $PROTECLI_VAULT; then
    # Build locally, deploy to protecli-vault
    nixos-rebuild "$ACTION" --flake .#protecli-vault \
        --target-host "$PROTECLI_VAULT_HOST" \
        --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
else
    # Rebuild using flake, auto-detects hostname
    sudo nixos-rebuild "$ACTION" --flake . &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
fi

if $DRY_RUN; then
    echo "Dry run succeeded!"
    popd
    exit 0
fi

# Get current generation metadata
current=$(nixos-rebuild list-generations | grep current)

# Commit all changes with the generation metadata
git commit -am "$current"

# Back to where you were
popd

# Notify all OK!
notify-send -e "NixOS Rebuilt OK!" --icon=software-update-available
