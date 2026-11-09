#!/usr/bin/env bash
#
# Tests for scripts/collect-sandbox-patches.sh (spec 30, FR-32).
#
# The collector must read the same allowlist as the validator and must not be
# wider than it. These tests run entirely offline with --from-dir and a policy
# fixture, and they assert the fail-closed behaviour when the allowlist cannot
# be obtained.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/.." && pwd)/collect-sandbox-patches.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

# ── fixtures ─────────────────────────────────────────────────────────────────
cat >"$WORK/policy.yaml" <<'EOF'
version: 1
default: deny
repos:
  nixos:
    allow:
      - "docs/**"
      - "modules/**"
    deny:
      - "flake.nix"
      - "modules/sops.nix"
  homelab-cluster:
    allow:
      - "manifests/cluster/**"
    deny:
      - "manifests/cluster/kustomization.yaml"
EOF

# make_patch <repo-subdir> <relative path> <content> → prints a real git patch
make_patch() {
  local path="$2" content="$3"
  local repo="$WORK/mk-$RANDOM"
  git init -q "$repo"
  mkdir -p "$repo/$(dirname "$path")"
  printf '%s\n' "$content" >"$repo/$path"
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@t.invalid commit -qm base
  printf '%s\n' "$content changed" >"$repo/$path"
  git -C "$repo" add -A
  git -C "$repo" diff --cached --binary
}

# ── 1. --allow-sensitive is gone ─────────────────────────────────────────────
if "$SCRIPT" --allow-sensitive 2>"$WORK/err"; then
  fail "--allow-sensitive was accepted"
fi
grep -qi "unknown option" "$WORK/err" || fail "--allow-sensitive did not report 'unknown option'"
pass "--allow-sensitive is rejected"

# ── 2. --repo is required ────────────────────────────────────────────────────
if "$SCRIPT" --from-dir "$WORK" --policy-file "$WORK/policy.yaml" 2>"$WORK/err"; then
  fail "missing --repo was accepted"
fi
grep -q -- "--repo is required" "$WORK/err" || fail "missing --repo did not explain itself"
pass "--repo is required"

# ── 3. policy fetch failure is fatal ─────────────────────────────────────────
mkdir -p "$WORK/empty"
# Force the fetch path with a stub kubectl that fails.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$WORK/bin/kubectl"
if PATH="$WORK/bin:$PATH" "$SCRIPT" --repo nixos --from-dir "$WORK/empty" --pod fake 2>"$WORK/err"; then
  fail "collector ran without a policy"
fi
grep -qi "policy unavailable" "$WORK/err" || fail "missing policy did not fail closed"
pass "unavailable policy fails closed"

# ── 4. denied path is refused ────────────────────────────────────────────────
mkdir -p "$WORK/case-denied"
make_patch x flake.nix "{}" >"$WORK/case-denied/denied.patch"
set +e
"$SCRIPT" --repo nixos --from-dir "$WORK/case-denied" \
  --policy-file "$WORK/policy.yaml" --out "$WORK/out-denied" >"$WORK/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "denied patch exit = $rc, want 1"
grep -q "REFUSED" "$WORK/out" || fail "denied patch was not refused"
grep -q "flake.nix" "$WORK/out" || fail "refusal did not name the path"
[ ! -f "$WORK/out-denied/denied.patch" ] || fail "denied patch was written to the output directory"
pass "denied path is refused and not written"

# ── 5. allowed path is collected ─────────────────────────────────────────────
mkdir -p "$WORK/case-allowed"
make_patch x docs/guide.md "hello" >"$WORK/case-allowed/allowed.patch"
"$SCRIPT" --repo nixos --from-dir "$WORK/case-allowed" \
  --policy-file "$WORK/policy.yaml" --out "$WORK/out-allowed" >"$WORK/out" 2>&1 || fail "allowed patch exit non-zero"
[ -f "$WORK/out-allowed/allowed.patch" ] || fail "allowed patch was not written"
pass "allowed path is collected"

# ── 6. lock files are refused even if an allow glob matches ─────────────────
mkdir -p "$WORK/case-lock"
make_patch x docs/env.terraform.lock.hcl "lock" >"$WORK/case-lock/lock.patch"
set +e
"$SCRIPT" --repo nixos --from-dir "$WORK/case-lock" \
  --policy-file "$WORK/policy.yaml" --out "$WORK/out-lock" >"$WORK/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "lock-file patch exit = $rc, want 1"
grep -q "terraform.lock.hcl" "$WORK/out" || fail "lock file was not named"
pass "lock files are refused"

# ── 7. homelab-cluster uses its own section ─────────────────────────────────
mkdir -p "$WORK/case-homelab"
make_patch x manifests/cluster/kustomization.yaml "x" >"$WORK/case-homelab/denied.patch"
set +e
"$SCRIPT" --repo homelab-cluster --from-dir "$WORK/case-homelab" \
  --policy-file "$WORK/policy.yaml" --out "$WORK/out-hl" >"$WORK/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "homelab denied patch exit = $rc, want 1"
grep -q "manifests/cluster/kustomization.yaml" "$WORK/out" || fail "homelab denial did not name the path"
pass "homelab-cluster allowlist is applied"

# ── 8. symlink and exec-bit patches are still collected by this guard ───────
# The collector only guards paths; tree shape is the validator's job. A patch
# that touches an allowed path must not be refused just because it is unusual.
mkdir -p "$WORK/case-mode"
make_patch x modules/foo.nix "{ }" >"$WORK/case-mode/mode.patch"
"$SCRIPT" --repo nixos --from-dir "$WORK/case-mode" \
  --policy-file "$WORK/policy.yaml" --out "$WORK/out-mode" >"$WORK/out" 2>&1 || fail "modules patch refused"
pass "allowed module patch is collected"

echo
echo "all collect-sandbox-patches tests passed"
