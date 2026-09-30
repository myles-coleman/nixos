#!/usr/bin/env bash
# Install a host's age key at /var/lib/sops-nix/key.txt (0600 root:root) over SSH.
# Usage: provision-host-key.sh <host-or-ip> [ssh-user]
set -euo pipefail

host="${1:?usage: provision-host-key.sh <host-or-ip> [ssh-user]}"
user="${2:-bee}"
key="${AGE_KEY_DIR:-$HOME/.config/sops/age/hosts}/$host.key"

if [ ! -f "$key" ]; then
  echo "missing private key: $key" >&2
  exit 1
fi

ssh "$user@$host" 'sudo install -d -m 0700 /var/lib/sops-nix'
ssh "$user@$host" 'sudo tee /var/lib/sops-nix/key.txt >/dev/null' <"$key"
ssh "$user@$host" 'sudo chown root:root /var/lib/sops-nix/key.txt && sudo chmod 0600 /var/lib/sops-nix/key.txt'
ssh "$user@$host" 'sudo ls -l /var/lib/sops-nix/key.txt'
