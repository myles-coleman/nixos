#!/usr/bin/env bash
set -euo pipefail

# verify-answer-key.sh - verify the detached signature on the Stage 1 answer key.
#
# The answer key is public challenge data, not a credential. The signature
# proves the harness is using the key that the operator signed, not a copy the
# target or a compromised component substituted.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dir="${repo_root}/config/redteam"
key="${dir}/juice-shop-answer-key.json"
sig="${key}.sig"
allowed="${dir}/allowed_signers"

for f in "$key" "$sig" "$allowed"; do
  [ -f "$f" ] || {
    echo "verify-answer-key: missing $f" >&2
    exit 1
  }
done

ssh-keygen -Y verify \
  -f "$allowed" \
  -I redteam-answer-key \
  -n redteam-answer-key \
  -s "$sig" < "$key" >/dev/null

echo "verify-answer-key: OK ($key)"
