#!/usr/bin/env bash
# check-tools.sh — assert that the sandbox image ships the exact pinned
# toolchain promised by spec 30, FR-56.
#
# Runs inside the built image from .github/workflows/build-images.yaml BEFORE
# the image is pushed, and locally for debugging. Expected versions come from
# the environment so this file and the Dockerfile read from one table; the
# defaults below must match the ARG/ENV pins in ./Dockerfile.
#
# Usage:
#   ./check-tools.sh
#   docker run --rm <image> /opt/sandbox/check-tools.sh
#
# Exit status is 0 only when every tool reports the expected version.
set -euo pipefail

GIT_VERSION="${GIT_VERSION:-2.39.5-0+deb12u3}"
CURL_VERSION="${CURL_VERSION:-7.88.1-10+deb12u15}"
JQ_VERSION="${JQ_VERSION:-1.8.2}"
ALEJANDRA_VERSION="${ALEJANDRA_VERSION:-4.1.0}"
STATIX_VERSION="${STATIX_VERSION:-0.5.8}"
DEADNIX_VERSION="${DEADNIX_VERSION:-1.3.2}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-5.8.3}"
HELM_VERSION="${HELM_VERSION:-4.3.1}"
KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-0.8.0}"
YAMLLINT_VERSION="${YAMLLINT_VERSION:-1.38.0}"
OPENCODE_VERSION="${OPENCODE_VERSION:-2.0.23}"

checked=0
failed=0

pass() { printf 'PASS  %-12s %s\n' "$1" "$2"; checked=$((checked + 1)); }
fail() { printf 'FAIL  %-12s expected %s, got %s\n' "$1" "$2" "$3" >&2; failed=$((failed + 1)); }

expect() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name" "$actual"
  else
    fail "$name" "$expected" "$actual"
  fi
}

# Debian package version with the epoch stripped, so it matches the pin table
# (for example 2.39.5-0+deb12u3, not 1:2.39.5-0+deb12u3).
pkg_version() {
  if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null | sed -E 's/^[0-9]+://'
  else
    printf 'dpkg-query-unavailable'
  fi
}

last_field() {
  awk '{print $NF}'
}

kustomize_version() {
  kustomize version 2>/dev/null \
    | sed -n 's/.*\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' \
    | head -1 \
    | sed 's/^v//'
}

helm_version() {
  helm version --short 2>/dev/null | sed -E 's/^v//; s/\+.*$//'
}

kubeconform_version() {
  kubeconform -v 2>/dev/null | sed -E 's/^v//'
}

expect git "$GIT_VERSION" "$(pkg_version git)"
expect curl "$CURL_VERSION" "$(pkg_version curl)"
expect jq "$JQ_VERSION" "$(jq --version 2>/dev/null | sed 's/^jq-//')"
expect alejandra "$ALEJANDRA_VERSION" "$(alejandra --version 2>/dev/null | last_field)"
expect statix "$STATIX_VERSION" "$(statix --version 2>/dev/null | last_field)"
expect deadnix "$DEADNIX_VERSION" "$(deadnix --version 2>/dev/null | last_field)"
expect kustomize "$KUSTOMIZE_VERSION" "$(kustomize_version)"
expect helm "$HELM_VERSION" "$(helm_version)"
expect kubeconform "$KUBECONFORM_VERSION" "$(kubeconform_version)"
expect yamllint "$YAMLLINT_VERSION" "$(yamllint --version 2>/dev/null | last_field)"
# `opencode --version` prints "opencode v2.0.23", so strip the program name
# rather than comparing the whole line.
expect opencode "v${OPENCODE_VERSION}" \
  "$(opencode --version 2>/dev/null | sed -E 's/^opencode[[:space:]]+//')"

if [ "$failed" -ne 0 ]; then
  printf '\n%d of %d tool version checks failed.\n' "$failed" "$((checked + failed))" >&2
  exit 1
fi

printf '\nAll %d tool version checks passed.\n' "$checked"
