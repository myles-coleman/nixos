# syntax=docker/dockerfile:1
#
# AMD64 sandbox image for the OpenCode agent instance that runs as a Kubernetes
# Agent Sandbox under gVisor (spec 20, Unit 4).
#
# Pinned to the SAME OpenCode v2.0.23 as the flake's `opencodeV2` input
# (github:anomalyco/opencode/v2.0.23), so the sandbox matches the nspawn instance
# it replaces.
#
# Distribution: v2 is NOT published as a GitHub release asset (the `v2.0.23` git
# tag has no GitHub Release), and it is not on the `opencode-ai` npm package
# (whose `latest` is the v1 line). The published artifact for the v2 line is the
# npm package `@opencode/cli`, whose per-platform binary arrives via the
# `@opencode/cli-linux-x64` optional dependency. Install that, pinned by version.
#
# This image is amd64-only and can only ever schedule on the dedicated amd64
# `sandbox-node` (the RuntimeClass nodeSelector pins it). The cluster's usual
# arm64 requirement is a deliberate, node-scoped exception for this workload.
#
# Build:
#   docker build --platform linux/amd64 -t ghcr.io/myles-coleman/opencode-sandbox:v2.0.23 .
#   docker push ghcr.io/myles-coleman/opencode-sandbox:v2.0.23
#
# Then pin the digest in manifests/cluster/agent-sandbox/sandbox.yaml. CI can do
# the build/push and print the digest: .github/workflows/sandbox-image.yaml.
#
# Edit-only: there is NO Nix in this image. The nspawn instance could `nix build`
# because it bind-mounted the host /nix/store and the Nix daemon socket; neither
# is possible in a Kubernetes gVisor pod. The agent edits files and the operator
# (or CI) builds. See ./AGENTS.md, which overrides the repo's own AGENTS.md.

FROM --platform=linux/amd64 node:22-bookworm-slim

ARG OPENCODE_VERSION=2.0.23

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils curl git ripgrep tar unzip \
    && rm -rf /var/lib/apt/lists/*

# The published v2 distribution: @opencode/cli pulls the matching
# @opencode/cli-linux-x64 binary. Fail the build early if the pinned version does
# not resolve or does not report the expected version.
RUN npm install --global "@opencode/cli@${OPENCODE_VERSION}" \
    && opencode --version \
    && opencode --version | grep -qF "v${OPENCODE_VERSION}"

# Unprivileged user; the workspace and $HOME live on a Retain PVC mounted here.
# fsGroup is ignored on local/hostPath volumes, so the owner is set explicitly.
# The Node base image already ships a `node` user at uid 1000, so it must go
# before we can claim 1000 for `agent` (the pod's runAsUser/runAsGroup).
RUN userdel --remove node 2>/dev/null || true
RUN useradd --create-home --uid 1000 --shell /bin/bash agent
USER 1000:1000
WORKDIR /home/agent

# The OpenCode server port (the pod's Service and the tailnet operator path use it).
EXPOSE 4096

ENTRYPOINT ["opencode"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "4096"]
