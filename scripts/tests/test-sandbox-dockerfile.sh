#!/usr/bin/env bash
# test-sandbox-dockerfile.sh — assert the OpenCode sandbox image installs the
# pinned toolchain promised by spec 30 FR-56 and no longer references the
# non-existent .github/workflows/sandbox-image.yaml (FR-57).
#
# The checks are intentionally text-based: this runs on the same secret-free
# path it guards, so it needs only bash, grep, awk, and sed.
#
# Usage:
#   scripts/tests/test-sandbox-dockerfile.sh
#   scripts/tests/test-sandbox-dockerfile.sh --help
#
# Exit: 0 only when every assertion passes; non-zero on the first failure.
set -euo pipefail

usage() {
  cat <<'EOF'
test-sandbox-dockerfile.sh — verify the sandbox image toolchain (FR-56, FR-57)

Checks:
  * images/opencode-sandbox/Dockerfile does NOT reference the stale
    .github/workflows/sandbox-image.yaml anywhere.
  * It does reference the real workflow, .github/workflows/build-images.yaml.
  * git, curl, jq, alejandra, statix, deadnix, kustomize, helm, kubeconform,
    and yamllint each appear as an install/pin.
  * The pinned versions match the expected table below (ARG/ENV or literal).
  * images/opencode-sandbox/check-tools.sh exists, is executable, and checks
    each of the ten tools plus `opencode --version`.
  * .github/workflows/build-images.yaml runs check-tools.sh for the
    opencode-sandbox image, before the push step.

Options:
  -h, --help   Show this help and exit.

Exit status is 0 only when every assertion passes. The first failure exits
non-zero immediately.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "test-sandbox-dockerfile: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SANDBOX_TEST_ROOT:-$(cd "$HERE/../.." && pwd)}"

DOCKERFILE="$ROOT/images/opencode-sandbox/Dockerfile"
CHECK_TOOLS="$ROOT/images/opencode-sandbox/check-tools.sh"
WORKFLOW="$ROOT/.github/workflows/build-images.yaml"

TOOLS=(git curl jq alejandra statix deadnix kustomize helm kubeconform yamllint)

# Expected pins — the single source of truth for this test.
declare -A PINS=(
  [OPENCODE_VERSION]="2.0.23"
  [ALEJANDRA_VERSION]="4.1.0"
  [STATIX_VERSION]="0.5.8"
  [DEADNIX_VERSION]="1.3.2"
  [KUSTOMIZE_VERSION]="5.8.3"
  [HELM_VERSION]="4.3.1"
  [KUBECONFORM_VERSION]="0.8.0"
  [YAMLLINT_VERSION]="1.38.0"
  [JQ_VERSION]="1.8.2"
  [GIT_VERSION]="2.39.5-0+deb12u3"
  [CURL_VERSION]="7.88.1-10+deb12u15"
)

# 1 file existence + 2 reference checks + 10 tools + 11 pins
# + 2 check-tools file checks + 10 tool checks + 1 opencode check
# + 1 workflow invocation + 1 push step + 1 ordering + 1 scoping
# + 1 entrypoint override = 42.
TOTAL=42
PASS=0

pass() { PASS=$((PASS + 1)); printf 'PASS %2d/%d  %s\n' "$PASS" "$TOTAL" "$*"; }
fail() { printf 'FAIL %2d/%d  %s\n' "$((PASS + 1))" "$TOTAL" "$*" >&2; exit 1; }

word_in_file() {
  local file="$1" word="$2"
  grep -qiE "(^|[^[:alnum:]_])${word}([^[:alnum:]_]|$)" "$file"
}

# 1. The Dockerfile exists.
[ -f "$DOCKERFILE" ] \
  || fail "Dockerfile missing: images/opencode-sandbox/Dockerfile"
pass "Dockerfile exists"

# 2. FR-57 — the stale workflow reference is gone.
if grep -qF '.github/workflows/sandbox-image.yaml' "$DOCKERFILE"; then
  fail "Dockerfile still references the stale .github/workflows/sandbox-image.yaml"
fi
pass "Dockerfile no longer references .github/workflows/sandbox-image.yaml"

# 3. FR-57 — the corrected workflow reference is present.
grep -qF 'build-images.yaml' "$DOCKERFILE" \
  || fail "Dockerfile does not reference build-images.yaml"
pass "Dockerfile references build-images.yaml"

# 4-13. FR-56 — every promised tool appears as an install/pin.
for tool in "${TOOLS[@]}"; do
  word_in_file "$DOCKERFILE" "$tool" \
    || fail "Dockerfile does not install/pin $tool"
  pass "Dockerfile installs/pins $tool"
done

# 14-24. FR-56 — the exact pinned versions (ARG/ENV or literal string).
for name in "${!PINS[@]}"; do
  value="${PINS[$name]}"
  if grep -qF "${name}=${value}" "$DOCKERFILE"; then
    pass "Dockerfile pins ${name}=${value} (ARG/ENV)"
  elif grep -qF "$value" "$DOCKERFILE"; then
    pass "Dockerfile pins ${value} for ${name} (literal)"
  else
    fail "Dockerfile does not pin ${name}=${value}"
  fi
done

# 25-26. FR-56 — the tool check script exists and is executable.
[ -f "$CHECK_TOOLS" ] \
  || fail "check-tools.sh missing: images/opencode-sandbox/check-tools.sh"
pass "check-tools.sh exists"

[ -x "$CHECK_TOOLS" ] \
  || fail "check-tools.sh is not executable"
pass "check-tools.sh is executable"

# 27-36. FR-56 — check-tools.sh checks every promised tool.
for tool in "${TOOLS[@]}"; do
  word_in_file "$CHECK_TOOLS" "$tool" \
    || fail "check-tools.sh does not check $tool"
  pass "check-tools.sh checks $tool"
done

# 37. FR-56 — check-tools.sh checks the OpenCode CLI itself.
grep -qE 'opencode[[:space:]]+--version' "$CHECK_TOOLS" \
  || fail "check-tools.sh does not run 'opencode --version'"
pass "check-tools.sh runs 'opencode --version'"

# 38. FR-56/FR-57 — build-images.yaml runs check-tools.sh.
[ -f "$WORKFLOW" ] \
  || fail "workflow missing: .github/workflows/build-images.yaml"

check_line="$(grep -nF 'check-tools.sh' "$WORKFLOW" | head -1 | cut -d: -f1 || true)"
[ -n "$check_line" ] \
  || fail "build-images.yaml does not run check-tools.sh"
pass "build-images.yaml runs check-tools.sh (line $check_line)"

# 39. There is a push step to order against.
push_line="$(grep -niE 'docker[[:space:]]+push|name:[[:space:]].*push' "$WORKFLOW" | head -1 | cut -d: -f1 || true)"
[ -n "$push_line" ] \
  || fail "build-images.yaml has no push step (expected 'docker push' or 'name: ... push')"
pass "build-images.yaml has a push step (line $push_line)"

# 40. The check-tools run step is before the push step.
[ "$check_line" -lt "$push_line" ] \
  || fail "check-tools.sh (line $check_line) is not before the push step (line $push_line)"
pass "check-tools.sh runs before the push step"

# 41. The check-tools invocation is scoped to the opencode-sandbox image.
ctx_start=$(( check_line > 10 ? check_line - 10 : 1 ))
ctx_end=$(( check_line + 10 ))
sed -n "${ctx_start},${ctx_end}p" "$WORKFLOW" | grep -qF 'opencode-sandbox' \
  || fail "check-tools.sh is not scoped to the opencode-sandbox image near line $check_line"
pass "check-tools.sh is scoped to the opencode-sandbox image"

# 42. The image entrypoint is `opencode`, so the check must replace it with
# --entrypoint; passing the script as an argument would run it through the CLI.
grep -qF -- '--entrypoint /opt/sandbox/check-tools.sh' "$WORKFLOW" \
  || fail "check-tools.sh is not invoked with --entrypoint (the image entrypoint is opencode)"
pass "check-tools.sh replaces the image entrypoint"

[ "$PASS" -eq "$TOTAL" ] \
  || { echo "test-sandbox-dockerfile: internal error: ran $PASS of $TOTAL checks" >&2; exit 1; }

printf '\nAll %d checks passed.\n' "$TOTAL"
