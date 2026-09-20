#!/usr/bin/env bash
set -euo pipefail

BASE_REPO="${BASE_REPO:-https://github.com/ggml-org/llama.cpp.git}"
BASE_COMMIT="${BASE_COMMIT:-aa39d7a3e145a88202793a89462d65e94a5fc25f}"
WORKDIR="${WORKDIR:-$PWD/.llama-candidates}"
DOCKERFILE="${DOCKERFILE:-.devops/rocm.Dockerfile}"
DOCKER_TARGET="${DOCKER_TARGET:-server}"
ROCM_ARCH="${ROCM_ARCH:-gfx1100}"
EXECUTE="${EXECUTE:-0}"
PROVENANCE="${PROVENANCE:-$WORKDIR/provenance.md}"

usage() {
  cat <<'EOF'
build-llama-candidates.sh - build pinned-base llama.cpp ROCm candidate images (Spec 04)

Usage:
  CANDIDATE=<pr> scripts/build-llama-candidates.sh [--execute]

Candidate (required):
  27861   GPU-resident LRU cache for host-offloaded MoE expert weights (primary)
  28136   qwen4exp direct reads for the lazy PLE table
  28248   persistent expert-pool variant (optional)

Behaviour:
  - clones llama.cpp, checks out BASE_COMMIT (default aa39d7a3e, the frozen
    baseline revision that already contains #27466), then merges the PR head.
  - builds the "server" stage of .devops/rocm.Dockerfile for gfx1100 only and
    tags llama-server-rocm-<pr>:<head-sha>.
  - dry-run by default; pass --execute or EXECUTE=1 to build (very slow, multi-GB
    ROCm toolchain). If the PR does not merge cleanly onto BASE_COMMIT, the script
    exits non-zero and requires a rebase/backport so the base stays fixed.

Environment overrides:
  BASE_REPO, BASE_COMMIT, WORKDIR, DOCKERFILE, DOCKER_TARGET, ROCM_ARCH, EXECUTE
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--execute" ]]; then
  EXECUTE=1
fi

candidate="${CANDIDATE:-${1:-}}"
case "$candidate" in
  27861) pr_ref="refs/pull/27861/head"; purpose="GPU-resident LRU cache for host-offloaded MoE expert weights";;
  28136) pr_ref="refs/pull/28136/head"; purpose="qwen4exp direct reads for the lazy PLE table";;
  28248) pr_ref="refs/pull/28248/head"; purpose="persistent expert-pool variant (optional)";;
  *) usage; exit 2;;
esac

for tool in git docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 127; }
done

src="$WORKDIR/llama.cpp"
if [[ ! -d "$src/.git" ]]; then
  mkdir -p "$WORKDIR"
  git clone "$BASE_REPO" "$src"
fi
git -C "$src" fetch --quiet origin "$BASE_COMMIT" "$pr_ref"
git -C "$src" checkout --quiet --detach "$BASE_COMMIT"
head_sha="$(git -C "$src" rev-parse FETCH_HEAD)"
if ! git -C "$src" merge --no-edit FETCH_HEAD >/dev/null 2>&1; then
  git -C "$src" merge --abort 2>/dev/null || true
  echo "candidate $candidate does not merge cleanly onto $BASE_COMMIT; rebase/backport required" >&2
  exit 3
fi
merged_sha="$(git -C "$src" rev-parse HEAD)"
tag="llama-server-rocm-$candidate:$head_sha"
build_cmd=(docker build -f "$src/$DOCKERFILE" --target "$DOCKER_TARGET"
  --build-arg "APP_VERSION=candidate-$candidate"
  --build-arg "APP_REVISION=$head_sha"
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  --build-arg "ROCM_DOCKER_ARCH=$ROCM_ARCH"
  -t "$tag" "$src")

cat <<EOF
candidate:   $candidate ($purpose)
base commit: $BASE_COMMIT (contains #27466)
PR ref:      $pr_ref
PR head:     $head_sha
merged:      $merged_sha
image tag:   $tag
build:       ${build_cmd[*]}
EOF

if [[ "$EXECUTE" != "1" ]]; then
  echo "dry-run: not building (pass --execute or EXECUTE=1 to build)" >&2
  exit 0
fi

"${build_cmd[@]}"
mkdir -p "$WORKDIR"
{
  echo "## candidate $candidate"
  echo
  echo "- purpose: $purpose"
  echo "- base repo: $BASE_REPO"
  echo "- base commit: $BASE_COMMIT (contains #27466)"
  echo "- PR ref: $pr_ref"
  echo "- PR head: $head_sha"
  echo "- merged commit: $merged_sha"
  echo "- image tag: $tag"
  echo "- dockerfile/target/arch: $DOCKERFILE / $DOCKER_TARGET / $ROCM_ARCH"
  echo "- built (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
} >> "$PROVENANCE"
echo "recorded provenance in $PROVENANCE" >&2
