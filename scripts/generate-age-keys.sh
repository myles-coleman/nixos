#!/usr/bin/env bash
# Generate one age key per host under ~/.config/sops/age/hosts and print the
# public halves to paste into .sops.yaml. Existing keys are kept.
set -euo pipefail

default_hosts=(bee-pc bee-gpd homelab bee-gpu-server protecli-vault pikvm)
hosts=("$@")
if [ "${#hosts[@]}" -eq 0 ]; then
  hosts=("${default_hosts[@]}")
fi

if ! command -v age-keygen >/dev/null 2>&1; then
  echo "age-keygen not found; run inside 'nix shell nixpkgs#age'" >&2
  exit 1
fi

out="${AGE_KEY_DIR:-$HOME/.config/sops/age/hosts}"
mkdir -p "$out"
chmod 700 "$out"

for host in "${hosts[@]}"; do
  key="$out/$host.key"
  if [ -f "$key" ]; then
    echo "kept    $host"
  else
    age-keygen -o "$key" >/dev/null 2>&1
    chmod 600 "$key"
    echo "created $host"
  fi
  printf '%s\t%s\n' "$host" "$(age-keygen -y "$key")"
done
