#!/usr/bin/env bash
set -euo pipefail

# probe-lab.sh - fail-closed reachability matrix for the spec 31 lab plane.
#
# Runs a fixed set of TCP probes and compares each result with an expected
# allow/deny. Exits non-zero and names the destination on any mismatch.
#
# Usage:
#   probe-lab.sh [--namespace NAME] [--lab-iface NAME]
#
# Environment:
#   PROBE_EXTRA  extra rows, one per line: "ip port expected label".
#                The self-test uses this to seed a reachable deny.

namespace=""
lab_iface="lab0"
skip_l3_check=false

usage() {
  sed -n '2,14p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --namespace)
      [ $# -ge 2 ] || { echo "--namespace requires a value" >&2; exit 2; }
      namespace="$2"
      shift 2
      ;;
    --lab-iface)
      [ $# -ge 2 ] || { echo "--lab-iface requires a value" >&2; exit 2; }
      lab_iface="$2"
      shift 2
      ;;
    --skip-l3-check)
      skip_l3_check=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

run() {
  if [ -n "$namespace" ]; then
    ip netns exec "$namespace" "$@"
  else
    "$@"
  fi
}

probe_tcp() {
  local ip="$1" port="$2"
  # A successful connect is the only "allow". Timeout, refusal, and
  # unreachable all count as "deny".
  run timeout 2 bash -c "exec 3<>/dev/tcp/${ip}/${port}" 2>/dev/null
}

rows=(
  "10.0.0.151 8443 deny broker-br0-control"
  "10.99.0.1 8443 deny broker-lab0-control"
  "10.0.0.150 22 deny homelab-ssh"
  "10.0.0.150 2049 deny homelab-nfs"
  "10.0.0.150 445 deny homelab-smb"
  "10.0.0.99 443 deny metallb-traefik"
  "10.0.0.200 6443 deny kube-vip"
  "10.0.0.140 6443 deny k3s-api"
  "10.43.0.1 443 deny service-cidr"
  "10.42.5.24 4096 deny pod-cidr"
  "169.254.169.254 80 deny imds"
  "1.1.1.1 443 deny public-internet"
  "127.0.0.1 1 deny loopback-no-listener"
)

if [ -n "${PROBE_EXTRA:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && rows+=("$line")
  done <<< "$PROBE_EXTRA"
fi

failures=0
printf '%-18s %-6s %-8s %-8s %-6s %s\n' "DEST" "PORT" "EXPECTED" "ACTUAL" "RESULT" "LABEL"
for row in "${rows[@]}"; do
  read -r ip port expected label <<< "$row"
  if probe_tcp "$ip" "$port"; then
    actual="allow"
  else
    actual="deny"
  fi

  result="PASS"
  if [ "$actual" != "$expected" ]; then
    result="FAIL"
    failures=$((failures + 1))
  fi
  printf '%-18s %-6s %-8s %-8s %-6s %s\n' "$ip" "$port" "$expected" "$actual" "$result" "$label"
done

# The lab interface must have no host L3 identity. This is a rule, not an
# absence: the nftables policy is the boundary, and this check keeps a future
# edit from quietly adding an address.
# The no-L3 check applies to the host bridge, not to the probe endpoint inside
# a namespace (which must have an address to generate traffic) or to a guest
# that is itself a lab host.
if [ "$skip_l3_check" != true ] && [ -z "$namespace" ] && run ip link show "$lab_iface" >/dev/null 2>&1; then
  if run ip -4 addr show dev "$lab_iface" | grep -q 'inet '; then
    echo "FAIL: $lab_iface has an IPv4 address" >&2
    failures=$((failures + 1))
  fi
  if run ip -6 addr show dev "$lab_iface" scope link | grep -q 'fe80'; then
    echo "FAIL: $lab_iface has an IPv6 link-local address" >&2
    failures=$((failures + 1))
  fi
fi

if [ "$skip_l3_check" != true ] && [ -z "$namespace" ]; then
  forwarding="$(sysctl -n net.ipv4.conf.lab0.forwarding 2>/dev/null || echo missing)"
  if [ "$forwarding" != "0" ]; then
    echo "FAIL: net.ipv4.conf.lab0.forwarding is '$forwarding', expected 0" >&2
    failures=$((failures + 1))
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "probe-lab: $failures unexpected result(s)" >&2
  exit 1
fi

echo "probe-lab: all expectations met"
