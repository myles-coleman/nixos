#!/usr/bin/env bash
#
# collect-sandbox-patches.sh — pull reviewable patch files out of the OpenCode
# sandbox without trusting it (spec 21, Unit 2).
#
# The sandbox has no repository write credential. Its only handoff is a set of
# `git format-patch` files on the workspace PVC. This script copies those files
# out for the operator to review and apply.
#
# Trust model
# -----------
# The sandbox is untrusted output. Therefore:
#   * only files matching `*.patch` in one flat directory are considered;
#   * each file is read individually with `kubectl exec -- cat`, never
#     `kubectl cp` and never a tar stream (tar has a path-traversal history);
#   * a file name containing `/`, `\` or `..` is refused outright, so a hostile
#     PVC cannot choose where the operator's disk gets written;
#   * patches touching CI workflows, the flake lock, sops config, secrets, the
#     guest module or authorized_keys are refused unless explicitly allowed.
#
# Usage:
#   collect-sandbox-patches.sh [--out DIR] [--pod NAME] [--namespace NS]
#                              [--from-dir DIR] [--allow-sensitive] [--help]
set -euo pipefail

NAMESPACE="${NAMESPACE:-agent-sandbox}"
LABEL_SELECTOR="${LABEL_SELECTOR:-app=opencode-sandbox}"
REMOTE_DIR="${REMOTE_DIR:-/home/agent/patches}"
OUT_DIR="./sandbox-patches"
POD=""
FROM_DIR=""
ALLOW_SENSITIVE=0

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --out DIR          Where to write the collected patches (default ./sandbox-patches)
  --pod NAME         Read from this pod instead of resolving the label selector
  --namespace NS     Namespace of the sandbox (default agent-sandbox)
  --from-dir DIR     Read from a local directory instead of the cluster. Used for
                     testing the guard; no kubectl involved.
  --allow-sensitive  Permit patches that touch the protected paths (still reported)
  --help             Show this help

Exit status:
  0  every patch was collected and none was refused
  1  a patch was refused, or a file failed validation
  2  usage error, or no sandbox pod could be resolved
EOF
}

die() {
  echo "collect-sandbox-patches: $*" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out)
      [ "$#" -ge 2 ] || die "--out needs a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --pod)
      [ "$#" -ge 2 ] || die "--pod needs a value"
      POD="$2"
      shift 2
      ;;
    --namespace)
      [ "$#" -ge 2 ] || die "--namespace needs a value"
      NAMESPACE="$2"
      shift 2
      ;;
    --from-dir)
      [ "$#" -ge 2 ] || die "--from-dir needs a value"
      FROM_DIR="$2"
      shift 2
      ;;
    --allow-sensitive)
      ALLOW_SENSITIVE=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

# ── protected paths ───────────────────────────────────────────────────────────
#
# A patch touching any of these changes the mechanism that deploys, the pin that
# determines what gets built, the store that holds the secrets, the guest module
# that defines the boundary this whole feature is about, or SSH access. Each one
# turns "the operator reviews a diff" into "the operator must audit the harness".
is_sensitive() {
  local path="$1"
  case "$path" in
    .github/workflows/*) return 0 ;;
    flake.lock) return 0 ;;
    .sops.yaml) return 0 ;;
    secrets/*) return 0 ;;
    hosts/homelab/modules/sandbox-node.nix) return 0 ;;
    */authorized_keys | authorized_keys) return 0 ;;
  esac
  return 1
}

# Extract every file path a patch touches. `diff --git a/X b/X` covers modified
# and deleted files; the `+++ b/X` / `--- a/X` lines cover new files and renames.
patch_paths() {
  sed -n \
    -e 's|^diff --git a/\(.*\) b/.*$|\1|p' \
    -e 's|^+++ b/\(.*\)$|\1|p' \
    -e 's|^--- a/\(.*\)$|\1|p' \
    "$1" | grep -v '^/dev/null$' | sort -u
}

# ── source ────────────────────────────────────────────────────────────────────
if [ -n "$FROM_DIR" ]; then
  [ -d "$FROM_DIR" ] || die "--from-dir is not a directory: $FROM_DIR"
  list_files() { ls -1 "$FROM_DIR"/*.patch 2>/dev/null || true; }
  fetch_file() { cat -- "$1"; }
else
  command -v kubectl >/dev/null 2>&1 || die "kubectl not found"

  if [ -z "$POD" ]; then
    POD="$(kubectl -n "$NAMESPACE" get pod -l "$LABEL_SELECTOR" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  [ -n "$POD" ] || die "no sandbox pod matching '$LABEL_SELECTOR' in namespace '$NAMESPACE'"

  echo "Sandbox pod: $NAMESPACE/$POD"
  list_files() {
    kubectl -n "$NAMESPACE" exec "$POD" -- sh -c "ls -1 '$REMOTE_DIR'/*.patch 2>/dev/null || true"
  }
  fetch_file() {
    # Per-file read. Never `kubectl cp`, never a tar stream.
    kubectl -n "$NAMESPACE" exec "$POD" -- cat -- "$1"
  }
fi

mapfile -t FILES < <(list_files)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No patches found. The agent writes them to $REMOTE_DIR with:"
  echo "  git format-patch -o $REMOTE_DIR origin/main"
  exit 0
fi

mkdir -p "$OUT_DIR"

refused=0
collected=0

for src in "${FILES[@]}"; do
  name="$(basename -- "$src")"

  # Reject anything that could steer writes on the operator's disk.
  case "$name" in
    */* | *\\* | *..*)
      echo "REFUSED  $src — unsafe file name" >&2
      refused=1
      continue
      ;;
    *.patch) ;;
    *)
      echo "REFUSED  $src — not a .patch file" >&2
      refused=1
      continue
      ;;
  esac

  dest="$OUT_DIR/$name"
  fetch_file "$src" >"$dest"

  # A patch must at least look like one before we hand it to `git apply`.
  if ! grep -q '^diff --git ' "$dest"; then
    echo "REFUSED  $name — not a git patch (no 'diff --git' header)" >&2
    rm -f "$dest"
    refused=1
    continue
  fi

  sensitive_hits=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if is_sensitive "$path"; then
      sensitive_hits="${sensitive_hits}${path}"$'\n'
    fi
  done < <(patch_paths "$dest")

  if [ -n "$sensitive_hits" ]; then
    if [ "$ALLOW_SENSITIVE" -eq 1 ]; then
      echo "WARNING  $name touches protected paths (allowed by --allow-sensitive):" >&2
      printf '%s' "$sensitive_hits" | sed 's/^/           /' >&2
    else
      echo "REFUSED  $name touches protected paths:" >&2
      printf '%s' "$sensitive_hits" | sed 's/^/           /' >&2
      rm -f "$dest"
      refused=1
      continue
    fi
  fi

  echo
  echo "=== $name ==="
  git apply --stat "$dest" || {
    echo "REFUSED  $name — git could not parse the patch" >&2
    rm -f "$dest"
    refused=1
    continue
  }
  collected=$((collected + 1))
done

echo
echo "Collected $collected patch(es) into $OUT_DIR."
echo "Review the diff stat above, then apply the ones you accept with:"
echo "  git am $OUT_DIR/<name>.patch      # keeps authorship and message"
echo "  git apply $OUT_DIR/<name>.patch   # apply only, no commit"

if [ "$refused" -ne 0 ]; then
  echo >&2
  echo "One or more patches were refused. Nothing was applied." >&2
  exit 1
fi
