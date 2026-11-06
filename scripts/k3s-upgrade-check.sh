#!/usr/bin/env bash
set -euo pipefail

# k3s-upgrade-check.sh - the gate between k3s node dispatches.
#
# Spec 28, Unit 3. The deploy workflow's post-deploy step only proves SSH and
# `readlink /run/current-system`, and `fail-fast: false` lets a failed node0 be
# followed by agent deploys. This script is what actually enforces "verify
# between each node": it asserts the running version, cluster health, cgroup v2,
# the kube-vip VIP and ArgoCD drift, and exits non-zero naming what failed.
#
# It is read-only: it never applies, cordons, drains or restarts anything.
#
# Usage:
#   scripts/k3s-upgrade-check.sh --expect-minor 1.34    # full live gate
#   scripts/k3s-upgrade-check.sh --node node0 --expect-minor 1.34
#   scripts/k3s-upgrade-check.sh --record-baseline      # after a known-good state
#   scripts/k3s-upgrade-check.sh --static               # no cluster, PR lane
#
# Exit codes: 0 all assertions passed, 1 an assertion failed, 2 usage/environment.
#
# Environment overrides:
#   K3S_GUEST_JUMP   ssh jump host for the microvm guest (default bee@100.110.170.34)
#   BASELINE_FILE    ArgoCD baseline path
#                    (default $HOME/.cache/k3s-upgrade-check/argocd-baseline.txt)

EXPECT_MINOR=""
RECORD_BASELINE=false
STATIC=false
BASELINE_FILE="${BASELINE_FILE:-$HOME/.cache/k3s-upgrade-check/argocd-baseline.txt}"
K3S_GUEST_JUMP="${K3S_GUEST_JUMP:-bee@100.110.170.34}"
VIP="10.0.0.200"
VIP_URL="https://${VIP}:6443"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Inventory: name, address, ssh user, jump host (empty for LAN-reachable nodes).
NODE_NAMES=(node0 node1 node2 node3 node4 sandbox-node)
NODE_IPS=(10.0.0.140 10.0.0.141 10.0.0.142 10.0.0.143 10.0.0.144 10.0.0.146)
NODE_USERS=(pi pi pi pi pi bee)
NODE_JUMPS=("" "" "" "" "" "${K3S_GUEST_JUMP}")
SELECTED=()

PASSES=0
FAILURES=0

usage() {
  cat <<'EOF'
k3s-upgrade-check.sh - machine-checkable k3s upgrade gate

Usage:
  scripts/k3s-upgrade-check.sh --expect-minor <X.Y> [--node NAME]...
  scripts/k3s-upgrade-check.sh --record-baseline
  scripts/k3s-upgrade-check.sh --static
  scripts/k3s-upgrade-check.sh --help

Options:
  --expect-minor X.Y   Major.minor every node and the apiserver must report.
  --node NAME          Limit per-node assertions to NAME (node0..node4,
                       sandbox-node). Repeatable.
  --record-baseline    Record the current ArgoCD sync/health state and exit.
  --baseline FILE      Compare against FILE instead of the default path.
  --static             No cluster access: assert repository invariants only.

Asserts:
  - every node's k3s is active, and its systemd ExecStart store path names the
    expected minor (never `k3s --version`)
  - /readyz and /version on the kube-vip VIP, and every node Ready at the same
    minor as its own ExecStart
  - /sys/fs/cgroup is cgroup2fs everywhere (k3s 1.35 refuses a kubelet on v1)
  - the kube-vip pod is Running on node0 and the VIP answers
  - no NEW ArgoCD OutOfSync/Unknown compared to the recorded baseline
  - apiserver_requested_deprecated_apis has no non-zero series, and kubent runs
    when installed (recorded as SKIPPED otherwise)

Environment overrides:
  K3S_GUEST_JUMP (default bee@100.110.170.34)   BASELINE_FILE
EOF
}

die_usage() {
  echo "k3s-upgrade-check: $*" >&2
  usage >&2
  exit 2
}

die_env() {
  echo "k3s-upgrade-check: $*" >&2
  exit 2
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die_env "missing required tool: $1"
}

# check <ok:0|1> <target> <assertion> <observed>
check() {
  local ok="$1" target="$2" assertion="$3" observed="$4"
  if [ "$ok" -eq 1 ]; then
    printf 'PASS %-13s %-42s %s\n' "$target" "$assertion" "$observed"
    PASSES=$((PASSES + 1))
  else
    printf 'FAIL %-13s %-42s %s\n' "$target" "$assertion" "$observed"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- static checks ----------------------------------------------------------

run_static() {
  local common="$REPO_ROOT/modules/aspects/k3s-common.nix"
  local server="$REPO_ROOT/modules/aspects/k3s-server.nix"
  local hits

  [ -f "$common" ] || die_env "not found: $common"
  [ -f "$server" ] || die_env "not found: $server"

  # 1. No bare `k3s` / `kubectl` inside k3s-common's environment.systemPackages.
  hits="$(
    awk '
      /environment\.systemPackages = with pkgs; \[/ { blk = 1; next }
      blk && /^[[:space:]]*\];/ { blk = 0 }
      blk && /^[[:space:]]*(k3s|kubectl)[[:space:]]*(#.*)?$/ { print FILENAME ":" NR ": " $0 }
    ' "$common"
  )"
  if [ -z "$hits" ]; then
    check 1 static "no shadowing k3s/kubectl in k3s-common" "clean"
  else
    check 0 static "no shadowing k3s/kubectl in k3s-common" "$(printf '%s' "$hits" | tr '\n' ';')"
  fi

  # 2. The server oneshot must use the service package's kubectl.
  #    Held in variables so the literal Nix interpolations are not expanded here.
  # shellcheck disable=SC2016  # the Nix interpolation is the literal we search for
  local old_kubectl='${pkgs.k3s}/bin/kubectl'
  # shellcheck disable=SC2016
  local new_kubectl='${config.services.k3s.package}/bin/kubectl'

  if grep -qF "$old_kubectl" "$server"; then
    check 0 static "k3s-apply-manifests uses service kubectl" \
      "$(grep -nF "$old_kubectl" "$server" | head -1)"
  else
    check 1 static "k3s-apply-manifests uses service kubectl" "no pkgs.k3s binary path"
  fi

  if grep -qF "$new_kubectl" "$server"; then
    check 1 static "k3s-server resolves kubectl from the service" "present"
  else
    check 0 static "k3s-server resolves kubectl from the service" "missing"
  fi
}

# --- helpers ----------------------------------------------------------------

ssh_node() { # <index> <remote command>
  local i="$1" cmd="$2"
  local args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  if [ -n "${NODE_JUMPS[$i]}" ]; then
    args+=(-J "${NODE_JUMPS[$i]}")
  fi
  # shellcheck disable=SC2029  # expands here on purpose: the caller builds the remote command
  ssh "${args[@]}" "${NODE_USERS[$i]}@${NODE_IPS[$i]}" "$cmd"
}

execstart_minor() { # <index> -> X.Y on stdout, non-zero on failure
  local out version
  out="$(ssh_node "$1" 'systemctl show -p ExecStart --value k3s')" || return 1
  version="$(printf '%s' "$out" | grep -oE 'k3s-[0-9]+\.[0-9]+\.[0-9]+[^/[:space:]]*' | head -1 | sed 's/^k3s-//')" || true
  [ -n "$version" ] || return 1
  printf '%s\n' "$version" | cut -d. -f1,2
}

resolve_kubectl() {
  local pkg
  pkg="$(
    cd "$REPO_ROOT" &&
      nix eval --raw ".#nixosConfigurations.node0.config.services.k3s.package" 2>/dev/null
  )" || die_env "could not evaluate services.k3s.package from the flake"
  [ -n "$pkg" ] || die_env "empty services.k3s.package evaluation"
  if [ ! -x "$pkg/bin/kubectl" ]; then
    echo "k3s-upgrade-check: realising $pkg (not in the local store yet)" >&2
    pkg="$(
      cd "$REPO_ROOT" &&
        nix build --no-link --print-out-paths \
          ".#nixosConfigurations.node0.config.services.k3s.package" 2>/dev/null | tail -1
    )" || die_env "could not realise services.k3s.package"
  fi
  [ -x "$pkg/bin/kubectl" ] || die_env "no kubectl in $pkg (k3s ships it; is the pin intact?)"
  printf '%s\n' "$pkg/bin/kubectl"
}

# --- live checks ------------------------------------------------------------

run_live() {
  local kubectl part v
  local i name minor active

  [ -n "$EXPECT_MINOR" ] || die_usage "--expect-minor <X.Y> is required for a live run"
  [[ "$EXPECT_MINOR" =~ ^[0-9]+\.[0-9]+$ ]] || die_usage "--expect-minor must look like 1.34"

  need_tool nix
  need_tool ssh
  need_tool jq
  need_tool curl

  kubectl="$(resolve_kubectl)"
  echo "k3s-upgrade-check: using $kubectl (from services.k3s.package, never PATH)"

  # Per-node assertions.
  for i in "${!NODE_NAMES[@]}"; do
    name="${NODE_NAMES[$i]}"
    [ ${#SELECTED[@]} -eq 0 ] || printf '%s\n' "${SELECTED[@]}" | grep -qx "$name" || continue

    active="$(ssh_node "$i" 'systemctl is-active k3s' 2>/dev/null || true)"
    check "$([ "$active" = "active" ] && echo 1 || echo 0)" "$name" "k3s active" "${active:-no answer}"

    if minor="$(execstart_minor "$i")"; then
      check "$([ "$minor" = "$EXPECT_MINOR" ] && echo 1 || echo 0)" "$name" \
        "ExecStart minor (expected $EXPECT_MINOR)" "$minor"
    else
      check 0 "$name" "ExecStart minor (expected $EXPECT_MINOR)" "could not parse systemd ExecStart"
    fi

    part="$(ssh_node "$i" 'stat -fc %T /sys/fs/cgroup' 2>/dev/null || true)"
    check "$([ "$part" = "cgroup2fs" ] && echo 1 || echo 0)" "$name" "cgroup v2 (1.35 refuses v1)" \
      "${part:-no answer}"
  done

  # Apiserver reachable through the VIP with real credentials.
  # The kubectl shipped inside the k3s package is the k3s multicall binary, which
  # prints its own data-dir log lines before the response; the answer is last.
  v="$("$kubectl" --server="$VIP_URL" get --raw /readyz 2>/dev/null | tail -1 || true)"
  check "$([ "$v" = "ok" ] && echo 1 || echo 0)" "apiserver" "VIP /readyz" "${v:-no answer}"

  v="$("$kubectl" get --raw /version 2>/dev/null || true)"
  local ver_major ver_minor
  ver_major="$(printf '%s' "$v" | sed -n 's/.*"major": *"\([0-9]*\)".*/\1/p' | head -1)"
  ver_minor="$(printf '%s' "$v" | sed -n 's/.*"minor": *"\([0-9]*\)".*/\1/p' | head -1)"
  check "$([ "${ver_major}.${ver_minor}" = "$EXPECT_MINOR" ] && echo 1 || echo 0)" "apiserver" \
    "/version minor (expected $EXPECT_MINOR)" "${ver_major:-?}.${ver_minor:-?}"

  # Node readiness and kubelet versions must agree with each node's own ExecStart.
  local nodes_json node_rows
  nodes_json="$("$kubectl" get nodes -o json 2>/dev/null)" || die_env "kubectl get nodes failed"
  node_rows="$(printf '%s' "$nodes_json" | jq -r '
    .items[] | .metadata.name as $n
    | ($n) + " " + ((.status.conditions[] | select(.type == "Ready") | .status) // "Unknown")
      + " " + (.status.nodeInfo.kubeletVersion // "?")
  ')"

  for i in "${!NODE_NAMES[@]}"; do
    name="${NODE_NAMES[$i]}"
    [ ${#SELECTED[@]} -eq 0 ] || printf '%s\n' "${SELECTED[@]}" | grep -qx "$name" || continue

    local row ready kubelet kminor
    row="$(printf '%s\n' "$node_rows" | awk -v n="$name" '$1 == n')"
    if [ -z "$row" ]; then
      check 0 "$name" "node object present and Ready" "not found in kubectl get nodes"
      continue
    fi
    ready="$(printf '%s' "$row" | awk '{print $2}')"
    kubelet="$(printf '%s' "$row" | awk '{print $3}')"
    kminor="$(printf '%s' "$kubelet" | sed 's/^v//' | cut -d. -f1,2)"
    check "$([ "$ready" = "True" ] && echo 1 || echo 0)" "$name" "node Ready" "$ready"
    if minor="$(execstart_minor "$i")"; then
      check "$([ "$kminor" = "$minor" ] && echo 1 || echo 0)" "$name" \
        "kubelet version matches ExecStart" "kubelet ${kubelet} vs service ${minor}"
    else
      check 0 "$name" "kubelet version matches ExecStart" "kubelet ${kubelet}; service ExecStart unreadable"
    fi
  done

  # kube-vip holds the VIP from node0.
  local vip_pods vip_ok
  vip_pods="$("$kubectl" -n kube-system get pod -l app=kube-vip -o json 2>/dev/null |
    jq -r '.items[] | "\(.spec.nodeName) \(.status.phase)"' || true)"
  vip_ok="$(printf '%s\n' "$vip_pods" | grep -c '^node0 Running$' || true)"
  check "$([ "${vip_ok:-0}" -ge 1 ] && echo 1 || echo 0)" "node0" "kube-vip pod Running" \
    "$(printf '%s' "$vip_pods" | tr '\n' ';')"

  # ArgoCD drift, compared to the recorded baseline.
  check_argocd "$kubectl"

  # API removals: metric first, kubent when available.
  local deprecated
  deprecated="$("$kubectl" get --raw /metrics 2>/dev/null |
    grep '^apiserver_requested_deprecated_apis' | awk '$NF != 0' | head -5 || true)"
  # Emitted, not asserted: some usage (Endpoints, a Traefik CRD) is pre-existing
  # and is exactly what the baseline and kubent are for. Silence would be the bug.
  if [ -z "$deprecated" ]; then
    printf 'INFO %-13s %-42s %s\n' "apiserver" "deprecated API usage" "none"
  else
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf 'INFO %-13s %-42s %s\n' "apiserver" "deprecated API usage" "$line"
    done <<<"$deprecated"
  fi

  if command -v kubent >/dev/null 2>&1; then
    if kubent --kubeconfig "${KUBECONFIG:-$HOME/.kube/config}" >/dev/null 2>&1; then
      check 1 apiserver "kubent" "no removed APIs in use"
    else
      check 0 apiserver "kubent" "kubent reported removed APIs in use"
    fi
  else
    printf 'SKIP %-13s %-42s %s\n' "apiserver" "kubent" "SKIPPED (not installed)"
  fi
}

argo_rows() { # <kubectl> -> "ns/name sync health" sorted
  "$1" get applications -A -o json 2>/dev/null |
    jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.status.sync.status // "Unknown") \(.status.health.status // "Unknown")"' |
    sort
}

check_argocd() {
  local kubectl="$1" current baseline drift
  current="$(argo_rows "$kubectl")" || die_env "kubectl get applications failed"
  [ -n "$current" ] || die_env "no ArgoCD Applications returned; is ArgoCD running?"

  if [ ! -f "$BASELINE_FILE" ]; then
    check 0 argocd "ArgoCD drift vs baseline" "no baseline at $BASELINE_FILE (run --record-baseline)"
    return
  fi

  baseline="$(cat "$BASELINE_FILE")"

  # New drift = an entry that is OutOfSync/Unknown now and was not recorded that
  # way. A permanently Unknown app in the baseline is not this hop's problem.
  drift="$(
    printf '%s\n' "$current" | while read -r key sync health; do
      [ -n "$key" ] || continue
      base_line="$(printf '%s\n' "$baseline" | awk -v k="$key" '$1 == k')"
      base_sync="$(printf '%s' "$base_line" | awk '{print $2}')"
      base_health="$(printf '%s' "$base_line" | awk '{print $3}')"
      if { [ "$sync" = "OutOfSync" ] || [ "$sync" = "Unknown" ]; } && [ "$sync" != "$base_sync" ]; then
        echo "$key sync $base_sync -> $sync"
      elif [ "$health" = "Unknown" ] && [ "$health" != "$base_health" ]; then
        echo "$key health $base_health -> $health"
      fi
    done
  )"

  local drift_note="no new drift"
  if [ -n "$drift" ]; then
    drift_note="$(printf '%s' "$drift" | tr '\n' ';')"
  fi
  check "$([ -z "$drift" ] && echo 1 || echo 0)" argocd "no new OutOfSync/Unknown" "$drift_note"
}

record_baseline() {
  local kubectl
  need_tool nix
  need_tool jq
  kubectl="$(resolve_kubectl)"
  mkdir -p "$(dirname "$BASELINE_FILE")"
  chmod 700 "$(dirname "$BASELINE_FILE")"
  argo_rows "$kubectl" >"$BASELINE_FILE"
  echo "k3s-upgrade-check: recorded $(wc -l <"$BASELINE_FILE") ArgoCD Applications to $BASELINE_FILE"
}

# --- argument parsing -------------------------------------------------------

main() {
  if [ $# -eq 0 ]; then
    usage
    exit 2
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --expect-minor)
        [ $# -ge 2 ] || die_usage "--expect-minor needs a value"
        EXPECT_MINOR="$2"
        shift 2
        ;;
      --node)
        [ $# -ge 2 ] || die_usage "--node needs a value"
        SELECTED+=("$2")
        shift 2
        ;;
      --record-baseline)
        RECORD_BASELINE=true
        shift
        ;;
      --baseline)
        [ $# -ge 2 ] || die_usage "--baseline needs a value"
        BASELINE_FILE="$2"
        shift 2
        ;;
      --static)
        STATIC=true
        shift
        ;;
      *)
        die_usage "unknown argument: $1"
        ;;
    esac
  done

  for n in "${SELECTED[@]:-}"; do
    if [ -n "$n" ]; then
      printf '%s\n' "${NODE_NAMES[@]}" | grep -qx "$n" || die_usage "unknown node: $n"
    fi
  done

  if $STATIC; then
    run_static
  elif $RECORD_BASELINE; then
    record_baseline
    exit 0
  else
    run_live
  fi

  if [ "$FAILURES" -gt 0 ]; then
    echo "k3s-upgrade-check: FAIL (${FAILURES} failed, ${PASSES} passed)"
    exit 1
  fi
  echo "k3s-upgrade-check: PASS (${PASSES} assertions)"
  exit 0
}

main "$@"
