#!/usr/bin/env bash
# Install a host's age key at /var/lib/sops-nix/key.txt (0600 root:root) over SSH.
#
# Usage: provision-host-key.sh <host-or-ip> [ssh-user]
#
# The key is looked up by name under ~/.config/sops/age/hosts/<name>.key. When a
# Tailscale IP is given instead of a host name, it is mapped to the host name.
# Override the lookup with AGE_KEY_NAME=<name>.
set -euo pipefail

target="${1:?usage: provision-host-key.sh <host-or-ip> [ssh-user]}"
user="${2:-bee}"
key_dir="${AGE_KEY_DIR:-$HOME/.config/sops/age/hosts}"

resolve_name() {
  case "$1" in
    homelab | bee-gpu-server | protecli-vault | pikvm | bee-pc | bee-gpd | node0 | node1 | node2 | node3 | node4) echo "$1" ;;
    100.110.170.34) echo "homelab" ;;
    100.127.170.8) echo "bee-gpu-server" ;;
    100.112.185.27) echo "protecli-vault" ;;
    100.116.132.19) echo "pikvm" ;;
    *) echo "" ;;
  esac
}

name="${AGE_KEY_NAME:-$(resolve_name "$target")}"
key="$key_dir/$name.key"

if [ -z "$name" ] || [ ! -f "$key" ]; then
  echo "no private key for '$target' (looked for $key_dir/<name>.key)" >&2
  echo "available keys:" >&2
  find "$key_dir" -maxdepth 1 -name '*.key' -exec basename -s .key {} + 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi

echo "provisioning $name key to $user@$target"
ssh "$user@$target" 'sudo install -d -m 0700 /var/lib/sops-nix'
ssh "$user@$target" 'sudo tee /var/lib/sops-nix/key.txt >/dev/null' <"$key"
ssh "$user@$target" 'sudo chown root:root /var/lib/sops-nix/key.txt && sudo chmod 0600 /var/lib/sops-nix/key.txt'
ssh "$user@$target" 'sudo ls -l /var/lib/sops-nix/key.txt'
