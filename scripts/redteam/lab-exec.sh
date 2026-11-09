#!/usr/bin/env bash
set -euo pipefail

# lab-exec.sh - run a command inside a temporary namespace attached to lab0.
#
# Must run as root on homelab. The namespace gets 10.99.0.250/24 and no
# default route, so the command can reach lab0 hosts but nothing else.
#
# Usage: lab-exec.sh <command> [args...]

if [ "$#" -eq 0 ]; then
  echo "usage: lab-exec.sh <command> [args...]" >&2
  exit 2
fi

# The names match the nftables `tap-lab0-*` set, so this namespace is treated
# as a lab host: it may reach other lab hosts and nothing else.
ns="labexec"
veth="tap-lab0-exec"
peer="tap-lab0-exe"

cleanup() {
  ip netns del "$ns" 2>/dev/null || true
  ip link del "$peer" 2>/dev/null || true
  # Detaching a port makes the bridge recompute this sysctl from the global
  # default; restore the lab's steady state.
  sysctl -qw net.ipv4.conf.lab0.forwarding=0 2>/dev/null || true
  sysctl -qw net.ipv6.conf.lab0.disable_ipv6=1 2>/dev/null || true
}
trap cleanup EXIT

ip netns del "$ns" 2>/dev/null || true
ip link del "$peer" 2>/dev/null || true

ip netns add "$ns"
ip link add "$veth" type veth peer name "$peer"
sysctl -qw net.ipv4.conf."$peer".forwarding=0
ip link set "$peer" master lab0 up
ip link set "$veth" netns "$ns"

ip netns exec "$ns" ip addr add 10.99.0.250/24 dev "$veth"
ip netns exec "$ns" sysctl -qw net.ipv6.conf."$veth".disable_ipv6=1
ip netns exec "$ns" ip link set lo up
ip netns exec "$ns" ip link set "$veth" up

ip netns exec "$ns" "$@"
