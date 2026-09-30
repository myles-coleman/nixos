#!/usr/bin/env bash
# Purge the leaked k3s token path (rpi5/token) from every ref of a mirror clone.
# Run this on a fresh `git clone --mirror`; verify, then force-push all refs.
# Usage: purge-token-history.sh <mirror-clone-dir>
set -euo pipefail

dir="${1:?usage: purge-token-history.sh <mirror-clone-dir>}"
path="${TOKEN_PATH:-rpi5/token}"

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "git-filter-repo not found; run inside 'nix shell nixpkgs#git-filter-repo'" >&2
  exit 1
fi

echo "pre-purge references:"
git -C "$dir" rev-list --all --objects | grep -F "$path" || true

git -C "$dir" filter-repo --sensitive-data-removal --invert-paths --path "$path" --force

echo "verifying..."
if git -C "$dir" log --all --oneline -- "$path" | grep -q .; then
  echo "FAIL: path still present in history" >&2
  exit 1
fi
if git -C "$dir" rev-list --all --objects | grep -qF "$path"; then
  echo "FAIL: blob still reachable" >&2
  exit 1
fi

echo "purge complete."
echo "next: run gitleaks/trufflehog over the full history, then force-push all refs:"
echo "  git -C $dir push --force --mirror origin"
