#!/usr/bin/env bash
set -euo pipefail

# probe-lab-test.sh - prove probe-lab.sh fails closed.
#
# Creates a throwaway network namespace with a veth on lab0, starts a listener
# on an address the matrix expects to be denied, and asserts that the probe
# exits non-zero and names the seeded row.
#
# Requires root (ip netns) and python3.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="${repo_root}/scripts/redteam/probe-lab.sh"
ns="labprobe-test"
veth="veth-labprobe"
veth_peer="veth-lab-br"
address="10.99.0.250"
port="9999"
listener_pid=""

cleanup() {
  if [ -n "$listener_pid" ]; then
    kill "$listener_pid" 2>/dev/null || true
  fi
  ip netns del "$ns" 2>/dev/null || true
  # Detaching a port makes the bridge recompute this sysctl from the global
  # default. Restore the lab's steady state after the transient probe port.
  sysctl -qw net.ipv4.conf.lab0.forwarding=0 2>/dev/null || true
  sysctl -qw net.ipv6.conf.lab0.disable_ipv6=1 2>/dev/null || true
}
trap cleanup EXIT

ip netns del "$ns" 2>/dev/null || true
ip link del "$veth_peer" 2>/dev/null || true

ip netns add "$ns"
ip link add "$veth" type veth peer name "$veth_peer"
# lab0 inherits the forwarding value of its ports; keep the probe port at 0.
sysctl -qw net.ipv4.conf."$veth_peer".forwarding=0
ip link set "$veth_peer" master lab0 up
ip link set "$veth" netns "$ns"

ip netns exec "$ns" ip addr add "${address}/24" dev "$veth"
ip netns exec "$ns" sysctl -qw net.ipv6.conf."$veth".disable_ipv6=1
ip netns exec "$ns" ip link set lo up
ip netns exec "$ns" ip link set "$veth" up

ip netns exec "$ns" python3 -m http.server "$port" --bind "$address" >/dev/null 2>&1 &
listener_pid=$!
sleep 1

set +e
output="$(
  PROBE_EXTRA="${address} ${port} deny seeded-reachable" \
    "$probe" --namespace "$ns" --lab-iface "$veth" 2>&1
)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: probe-lab.sh accepted a reachable destination expected to be denied" >&2
  echo "$output" >&2
  exit 1
fi

if ! grep -q "seeded-reachable" <<< "$output"; then
  echo "FAIL: probe-lab.sh failed but did not name the seeded row" >&2
  echo "$output" >&2
  exit 1
fi

echo "probe-lab-test: PASS (seeded reachable destination was reported and the probe exited non-zero)"
echo "$output" | grep "seeded-reachable"
