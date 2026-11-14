#!/usr/bin/env bash
#
# Mutation proof for spec 30 Unit 5's sandbox-image checks (FR-56, FR-57).
#
# Each mutation is applied to a disposable copy of HEAD, the Dockerfile check is
# run, and the copy is restored. "caught" means the check exited non-zero.
#
# Usage: ./scripts/tests/mutation-sandbox-dockerfile.sh [--list]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

H="$WORK/repo"
mkdir -p "$H"
git -C "$REPO" archive HEAD | tar -x -C "$H"
cp -a "$H" "$WORK/pristine"

caught=0
missed=0
rows=()

restore() { rsync -a --delete "$WORK/pristine/" "$H/"; }

run() {
  local id="$1" desc="$2" snippet="$3"
  restore
  python3 - "$H" <<PY
import sys
root = sys.argv[1]
$snippet
PY
  if ( cd "$H" && ./scripts/tests/test-sandbox-dockerfile.sh >"$WORK/out" 2>&1 ); then
    missed=$((missed + 1))
    rows+=("$id|$desc|missed|$(grep -m1 PASS "$WORK/out" | head -c 100)")
  else
    caught=$((caught + 1))
    rows+=("$id|$desc|caught|$(grep -m1 FAIL "$WORK/out" | head -c 120)")
  fi
}

if [ "${1:-}" = "--list" ]; then
  grep -oE '^run M[0-9]+ "[^"]+"' "$0" | sed 's/^run /  /'
  exit 0
fi

run N1 "alejandra install block removed" '
p=root+"/images/opencode-sandbox/Dockerfile"
s=open(p).read()
start=s.index("# alejandra — musl binary")
end=s.index("# kustomize — tarball")
open(p,"w").write(s[:start]+s[end:])
'

run N2 "ALEJANDRA_VERSION changed to 4.0.0" '
p=root+"/images/opencode-sandbox/Dockerfile"
s=open(p).read().replace("ARG ALEJANDRA_VERSION=4.1.0","ARG ALEJANDRA_VERSION=4.0.0")
open(p,"w").write(s)
'

run N3 "stale sandbox-image.yaml reference reintroduced" '
p=root+"/images/opencode-sandbox/Dockerfile"
s=open(p).read()
open(p,"w").write("# see .github/workflows/sandbox-image.yaml\n"+s)
'

run N4 "check-tools moved after the push step" '
p=root+"/.github/workflows/build-images.yaml"
s=open(p).read()
start=s.index("      - name: Verify opencode-sandbox toolchain")
end=s.index("      - name: Push verified opencode-sandbox image")
block=s[start:end]
s=s[:start]+s[end:]
anchor=s.index("      - name: Record opencode-sandbox digest")
s=s[:anchor]+block+s[anchor:]
open(p,"w").write(s)
'

run N5 "opencode --version check removed" '
p=root+"/images/opencode-sandbox/check-tools.sh"
lines=[line for line in open(p).read().splitlines() if "expect opencode" not in line]
open(p,"w").write("\n".join(lines)+"\n")
'

run N6 "check-tools entrypoint override removed" '
p=root+"/.github/workflows/build-images.yaml"
s=open(p).read().replace("--entrypoint /opt/sandbox/check-tools.sh ","")
open(p,"w").write(s)
'

printf '\n%-4s %-48s %-7s %s\n' ID MUTATION RESULT DETAIL
for row in "${rows[@]}"; do IFS='|' read -r id desc res det <<<"$row"; printf '%-4s %-48s %-7s %s\n' "$id" "$desc" "$res" "$det"; done
printf '\ncaught=%d missed=%d total=%d\n' "$caught" "$missed" "$((caught + missed))"
[ "$missed" -eq 0 ]
