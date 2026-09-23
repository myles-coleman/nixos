#!/usr/bin/env bash
set -euo pipefail

# Keep the root nixpkgs pin aligned with the revision locked by
# nixos-raspberrypi, so the Raspberry Pi binary cache stays valid.
#
# The monorepo root nixpkgs must match the nixpkgs rev that
# nixos-raspberrypi pins; otherwise every RPi kernel/firmware build misses
# the vendor cache. nixos-raspberrypi's own nixpkgs input follows root, so
# the reference rev is read from its upstream flake.lock.
#
# Usage:
#   scripts/repin-nixpkgs-from-rpi.sh           # report alignment only
#   scripts/repin-nixpkgs-from-rpi.sh --apply    # re-pin root to the RPi rev

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RPI_REPO="${RPI_REPO:-nvmd/nixos-raspberrypi}"
RPI_REF="${RPI_REF:-main}"
RPI_LOCK_URL="https://raw.githubusercontent.com/${RPI_REPO}/${RPI_REF}/flake.lock"

usage() {
  cat <<'EOF'
repin-nixpkgs-from-rpi.sh - align root nixpkgs with nixos-raspberrypi

Usage:
  scripts/repin-nixpkgs-from-rpi.sh           report alignment only
  scripts/repin-nixpkgs-from-rpi.sh --apply    re-pin root nixpkgs to the RPi rev

Environment overrides:
  RPI_REPO   nixos-raspberrypi repo (default nvmd/nixos-raspberrypi)
  RPI_REF    ref to read the lock from (default main)
EOF
}

apply=false
case "${1:-}" in
  --apply) apply=true ;;
  -h | --help) usage; exit 0 ;;
  "") ;;
  *)
    usage
    exit 2
    ;;
esac

root_rev="$(python3 -c "import json;print(json.load(open('flake.lock'))['nodes']['nixpkgs']['locked']['rev'])")"
rpi_rev="$(curl -fsSL "$RPI_LOCK_URL" | python3 -c "import json,sys;print(json.load(sys.stdin)['nodes']['nixpkgs']['locked']['rev'])")"

echo "root nixpkgs rev:            $root_rev"
echo "nixos-raspberrypi nixpkgs:   $rpi_rev"

if [ "$root_rev" = "$rpi_rev" ]; then
  echo "ALIGNED: root nixpkgs matches nixos-raspberrypi"
  exit 0
fi

echo "MISMATCHED: root nixpkgs differs from nixos-raspberrypi"

if $apply; then
  nix flake lock --override-input nixpkgs "github:NixOS/nixpkgs/${rpi_rev}"
  echo "root nixpkgs re-pinned to $rpi_rev"
  exit 0
fi

echo "run with --apply to re-pin root nixpkgs to $rpi_rev"
exit 1
