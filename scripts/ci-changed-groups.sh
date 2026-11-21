#!/usr/bin/env bash
#
# Classify changed repository paths into build groups for the PR workflow
# (issue #114). Reads repository-relative paths on stdin, one per line, and
# writes exactly three `key=value` lines to stdout:
#
#   code=...  any code changed at all: the pin-guard, sandbox-image-check and
#             closure-diff jobs
#   x86=...   the five x86_64 hosts: bee-pc, bee-gpd, homelab, bee-gpu-server,
#             protecli-vault
#   arm=...   pikvm, rpi3 and the k3s node0-node4 fleet
#
# There are three classes. A path is *x86-only* when only x86 hosts consume it,
# *arm-only* when only the Raspberry Pi fleet and pikvm do, and *shared*
# otherwise. Anything the patterns below do not name is shared on purpose: an
# unrecognised path must over-build, never skip a host whose configuration the
# PR could have changed. A stale pattern here costs runner minutes; a missing
# one ships a host nobody built.
#
# arm-only is matched before x86-only because `config/pikvm/` would otherwise
# be read as an x86 `config/` path.
#
# Bash-3 style (no `mapfile`, no `${var,,}`) to match rebuild.sh. Exit status is
# always 0: this is a classifier, not a gate.
set -euo pipefail

is_arm_only() {
  case "$1" in
    hosts/node[0-4]/* | hosts/rpi3/* | hosts/pikvm/*) return 0 ;;
    modules/aspects/rpi-base.nix | modules/aspects/k3s-common.nix) return 0 ;;
    modules/aspects/k3s-server.nix | modules/aspects/k3s-agent.nix) return 0 ;;
    modules/aspects/k3s-token-sops.nix | modules/aspects/node-health.nix) return 0 ;;
    modules/rpi/* | modules/pikvm.nix | config/pikvm/*) return 0 ;;
  esac
  return 1
}

is_x86_only() {
  case "$1" in
    hosts/bee-pc/* | hosts/bee-gpd/* | hosts/homelab/*) return 0 ;;
    hosts/bee-gpu-server/* | hosts/protecli-vault/*) return 0 ;;
    modules/aspects/access.nix | modules/aspects/common.nix) return 0 ;;
    modules/aspects/desktop.nix | modules/aspects/dev-tools.nix) return 0 ;;
    modules/aspects/gaming.nix | modules/aspects/home-desktop.nix) return 0 ;;
    modules/aspects/home-zsh.nix | modules/aspects/cli-core.nix) return 0 ;;
    modules/aspects/cli-extras.nix | modules/aspects/server-base.nix) return 0 ;;
    modules/aspects/k8s.nix | modules/aspects/network.nix) return 0 ;;
    modules/aspects/networkmanager.nix | modules/aspects/nvidia.nix) return 0 ;;
    modules/aspects/sudo.nix | modules/steam-remote-play-client.nix) return 0 ;;
    config/mangohud/* | config/rofi/* | config/waybar/*) return 0 ;;
    config/oh-my-posh* | config/hyprland/*) return 0 ;;
    config/krisp-patcher.py | config/wallpaper1.jpg) return 0 ;;
    images/*) return 0 ;;
  esac
  return 1
}

code=false
x86=false
arm=false

# `|| [ -n "$path" ]` keeps a final line that has no trailing newline: a path
# dropped by the loop would be a path that never builds.
while IFS= read -r path || [ -n "$path" ]; do
  # An empty diff is one empty line, and classifies nothing.
  [ -n "$path" ] || continue

  # 1. Prose cannot change a build.
  case "$path" in
    *.md | docs/*) continue ;;
  esac

  # 2. The shell suites and the pin guard still run, but no host is built from
  #    a script.
  case "$path" in
    scripts/*)
      code=true
      continue
      ;;
  esac

  # 3. arm-only, before x86-only.
  if is_arm_only "$path"; then
    code=true
    arm=true
    continue
  fi

  # 4. x86-only.
  if is_x86_only "$path"; then
    code=true
    x86=true
    continue
  fi

  # 5. Unknown paths are shared: both groups build.
  code=true
  x86=true
  arm=true
done

printf 'code=%s\nx86=%s\narm=%s\n' "$code" "$x86" "$arm"
