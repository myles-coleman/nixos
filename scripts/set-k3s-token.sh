#!/usr/bin/env bash
# Store the rotated k3s server token in secrets/common.yaml. The token is read
# from stdin so it never appears in argv or shell history.
#
# Requires an admin identity that can decrypt common.yaml:
#   SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
#     nix shell nixpkgs#sops nixpkgs#jq -c scripts/set-k3s-token.sh
#
# Then paste the token and press Enter (Ctrl-D also accepted).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

for tool in sops jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool not found; run inside 'nix shell nixpkgs#sops nixpkgs#jq'" >&2
    exit 1
  }
done

printf 'Paste the new k3s server token: ' >&2
IFS= read -r token

if [ -z "${token:-}" ]; then
  echo "empty token; nothing set" >&2
  exit 1
fi

json="$(printf '%s' "$token" | jq -Rs .)"
sops --set "[\"k3s_server_token\"] $json" secrets/common.yaml
unset token json

echo "k3s_server_token set in secrets/common.yaml"
