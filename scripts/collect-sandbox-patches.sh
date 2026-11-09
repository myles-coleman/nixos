#!/usr/bin/env bash
#
# collect-sandbox-patches.sh — pull reviewable patch files out of the OpenCode
# sandbox, judged against the same allowlist the validator enforces.
#
# The sandbox has no repository write credential. Its only handoff is a set of
# `git format-patch` files on the workspace PVC. This script copies them out for
# operator review.
#
# Trust model
# -----------
# The sandbox is untrusted output. Therefore:
#   * only files matching `*.patch` in one flat directory are considered;
#   * each file is read individually with `kubectl exec -- cat`, never
#     `kubectl cp` and never a tar stream (tar has a path-traversal history);
#   * a file name containing `/`, `\` or `..` is refused outright;
#   * every touched path is judged against the canonical allowlist fetched from
#     the validator (spec 30, FR-32). There is no local copy and no override:
#     when the policy cannot be fetched, this script refuses to run.
#
# Usage:
#   collect-sandbox-patches.sh --repo <nixos|homelab-cluster> [options]
set -euo pipefail

NAMESPACE="${NAMESPACE:-agent-sandbox}"
LABEL_SELECTOR="${LABEL_SELECTOR:-app=opencode-sandbox}"
REMOTE_DIR="${REMOTE_DIR:-/home/agent/patches}"
OUT_DIR="./sandbox-patches"
POD=""
FROM_DIR=""
REPO=""
POLICY_FILE=""
VALIDATOR_URL="${VALIDATOR_URL:-https://validator.agent.internal:8443}"

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --repo NAME        Repository the patches target (required): nixos or
                     homelab-cluster. Selects the allowlist section.
  --out DIR          Where to write collected patches (default ./sandbox-patches)
  --pod NAME         Read from this pod instead of resolving the label selector
  --namespace NS     Namespace of the sandbox (default agent-sandbox)
  --from-dir DIR     Read from a local directory instead of the cluster.
  --policy-file FILE Test-only. Read the allowlist from a file instead of the
                     validator; only accepted together with --from-dir.
  --help             Show this help

Exit status:
  0  every patch was collected and none was refused
  1  a patch was refused, or a file failed validation
  2  usage error, no sandbox pod, or the allowlist could not be fetched
EOF
}

die() {
  echo "collect-sandbox-patches: $*" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) [ "$#" -ge 2 ] || die "--out needs a value"; OUT_DIR="$2"; shift 2 ;;
    --pod) [ "$#" -ge 2 ] || die "--pod needs a value"; POD="$2"; shift 2 ;;
    --namespace) [ "$#" -ge 2 ] || die "--namespace needs a value"; NAMESPACE="$2"; shift 2 ;;
    --from-dir) [ "$#" -ge 2 ] || die "--from-dir needs a value"; FROM_DIR="$2"; shift 2 ;;
    --repo) [ "$#" -ge 2 ] || die "--repo needs a value"; REPO="$2"; shift 2 ;;
    --policy-file) [ "$#" -ge 2 ] || die "--policy-file needs a value"; POLICY_FILE="$2"; shift 2 ;;
    --help | -h) usage; exit 0 ;;
    *)
      # --allow-sensitive was removed in spec 30 (FR-32). Keep the diagnostic
      # explicit so an old invocation fails loudly instead of silently running
      # with a wider policy.
      case "$1" in
        --allow-sensitive) die "unknown option: --allow-sensitive (removed; the allowlist is canonical)" ;;
        *) die "unknown option: $1 (try --help)" ;;
      esac
      ;;
  esac
done

[ -n "$REPO" ] || die "--repo is required (nixos or homelab-cluster)"
case "$REPO" in
  nixos | homelab-cluster) ;;
  *) die "unsupported repository: $REPO" ;;
esac
if [ -n "$POLICY_FILE" ] && [ -z "$FROM_DIR" ]; then
  die "--policy-file is only allowed with --from-dir"
fi

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

# ── canonical allowlist (FR-32) ───────────────────────────────────────────────
#
# One source: the validator serves the same file it enforces. No local copy is
# kept, and an unavailable policy is fatal — a manual path wider than the
# automated one is exactly the drift this feature exists to remove.
TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$TMP_WORK"' EXIT
POLICY="$TMP_WORK/policy.yaml"

fetch_policy() {
  if [ -n "$POLICY_FILE" ]; then
    cat -- "$POLICY_FILE"
    return
  fi
  kubectl -n "$NAMESPACE" exec "$POD" -- \
    curl -sS --fail --max-time 10 \
    --cacert /certs/ca.crt --cert /certs/tls.crt --key /certs/tls.key \
    "$VALIDATOR_URL/v1/policy"
}

if ! fetch_policy >"$POLICY" 2>/dev/null; then
  die "policy unavailable: refusing to run without the validator allowlist"
fi
[ -s "$POLICY" ] || die "policy unavailable: the validator returned an empty allowlist"

# ── path extraction and evaluation ────────────────────────────────────────────
patch_paths() {
  sed -n \
    -e 's|^diff --git a/\(.*\) b/.*$|\1|p' \
    -e 's|^+++ b/\(.*\)$|\1|p' \
    -e 's|^--- a/\(.*\)$|\1|p' \
    "$1" | grep -v '^/dev/null$' | sort -u
}

# Prints one denied path per line. Empty output means the patch is permitted.
# The allowlist is parsed from the validator's YAML with a deliberately small
# parser: this file's shape, no third-party dependency on the operator host.
evaluate_paths() {
  local patch="$1"
  local -a paths=()
  mapfile -t paths < <(patch_paths "$patch")
  if [ "${#paths[@]}" -eq 0 ]; then
    return 0
  fi
  python3 - "$REPO" "$POLICY" "${paths[@]}" <<'PY'
import re
import sys

repo = sys.argv[1]
text = open(sys.argv[2], encoding="utf-8").read()
paths = sys.argv[3:]

repos, cur, field = {}, None, None
for raw in text.splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    indent = len(raw) - len(raw.lstrip())
    line = raw.strip()
    if line == "repos:":
        continue
    if indent == 2 and line.endswith(":"):
        cur = line[:-1]
        repos[cur] = {"allow": [], "deny": []}
        field = None
    elif indent == 4 and line.endswith(":"):
        field = line[:-1]
    elif indent == 6 and line.startswith("- ") and cur and field in ("allow", "deny"):
        repos[cur][field].append(line[2:].strip().strip('"'))

if repo not in repos:
    print("<unknown repository>")
    sys.exit(0)

def glob_to_re(pattern):
    out, i = "", 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 2] == "**":
                out += ".*"
                i += 2
                continue
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        else:
            out += re.escape(c)
        i += 1
    return "^" + out + "$"

allow = [glob_to_re(p) for p in repos[repo]["allow"]]
deny = [glob_to_re(p) for p in repos[repo]["deny"]]

for path in paths:
    if path in ("", "/dev/null"):
        continue
    base = path.rsplit("/", 1)[-1]
    # Lock files are refused by a dedicated rule in the validator (FR-24), so the
    # manual path refuses them too.
    if base == "flake.lock" or path.endswith(".terraform.lock.hcl"):
        print(path)
        continue
    if any(re.match(d, path) for d in deny):
        print(path)
        continue
    if not any(re.match(a, path) for a in allow):
        print(path)
PY
}

# ── collection ────────────────────────────────────────────────────────────────
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

  denied="$(evaluate_paths "$dest")"
  if [ -n "$denied" ]; then
    echo "REFUSED  $name touches paths outside the $REPO allowlist:" >&2
    printf '%s\n' "$denied" | sed 's/^/           /' >&2
    rm -f "$dest"
    refused=1
    continue
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
echo "Collected $collected, refused $((${#FILES[@]} - collected))."

if [ "$refused" -ne 0 ]; then
  exit 1
fi
exit 0
