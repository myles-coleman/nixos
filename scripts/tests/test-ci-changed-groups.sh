#!/usr/bin/env bash
#
# Tests for scripts/ci-changed-groups.sh (issue #114).
#
# The classifier decides which host groups a PR builds. Its one safety
# property: a path it does not recognise must over-build (both groups), never
# skip a host whose configuration the PR could have changed. These assertions
# pin the three classes (x86-only, arm-only, shared) plus the arm-before-x86
# ordering that keeps `config/pikvm/` from being read as an x86 `config/` path.
#
# Usage: scripts/tests/test-ci-changed-groups.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/scripts/ci-changed-groups.sh"

TOTAL=16

fail() {
  printf 'FAIL %s/%s - %s\n' "$1" "$TOTAL" "$2" >&2
  exit 1
}

pass() {
  printf 'PASS %s/%s - %s\n' "$1" "$TOTAL" "$2"
}

# check <n> <label> <stdin> <expected stdout>
check() {
  local n="$1" label="$2" input="$3" want="$4" got lines
  if ! got="$(printf '%s' "$input" | "$SCRIPT")"; then
    fail "$n" "$label (classifier exited non-zero)"
  fi
  if [ "$got" != "$want" ]; then
    fail "$n" "$label (expected '$(printf '%s ' "$want")', got '$(printf '%s ' "$got")')"
  fi
  lines="$(printf '%s\n' "$got" | wc -l | tr -d ' ')"
  if [ "$lines" != 3 ]; then
    fail "$n" "$label (expected exactly 3 output lines, got $lines)"
  fi
  pass "$n" "$label"
}

NOTHING='code=false
x86=false
arm=false'
CODE='code=true
x86=false
arm=false'
ARM='code=true
x86=false
arm=true'
X86='code=true
x86=true
arm=false'
BOTH='code=true
x86=true
arm=true'

check 1 "a scripts/ change is code-only" "scripts/foo.sh" "$CODE"
check 2 "a markdown change affects nothing" "README.md" "$NOTHING"
check 3 "a k3s node change is arm-only" "hosts/node1/default.nix" "$ARM"
check 4 "the rpi-base aspect is arm-only" "modules/aspects/rpi-base.nix" "$ARM"
check 5 "modules/pikvm.nix is arm-only" "modules/pikvm.nix" "$ARM"
check 6 "config/pikvm/ is arm-only, not x86-only" "config/pikvm/main.yaml" "$ARM"
check 7 "the dev-tools aspect is x86-only" "modules/aspects/dev-tools.nix" "$X86"
check 8 "an x86 host is x86-only" "hosts/bee-gpd/default.nix" "$X86"
check 9 "config/waybar/ is x86-only" "config/waybar/config" "$X86"
check 10 "images/ is x86-only" "images/strata-rocm/Dockerfile" "$X86"
check 11 "flake.lock is shared" "flake.lock" "$BOTH"
check 12 "the tailscale aspect is shared with the k3s nodes" "modules/aspects/tailscale.nix" "$BOTH"
check 13 "modules/sops.nix is shared" "modules/sops.nix" "$BOTH"
check 14 "a markdown change plus an arm host is arm-only" "$(printf 'README.md\nhosts/node0/default.nix')" "$ARM"
check 15 "an arm host plus an x86 host is both" "$(printf 'hosts/node0/default.nix\nhosts/bee-gpd/default.nix')" "$BOTH"
check 16 "empty input builds nothing" "" "$NOTHING"

printf '\nall %s assertions passed\n' "$TOTAL"
