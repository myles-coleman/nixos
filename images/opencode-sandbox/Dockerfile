# syntax=docker/dockerfile:1
#
# AMD64 sandbox image for the OpenCode agent instance that runs as a Kubernetes
# Agent Sandbox under gVisor (spec 20, Unit 4).
#
# Pinned to the SAME OpenCode v2.0.23 as the flake's `opencodeV2` input
# (github:anomalyco/opencode/v2.0.23), so the sandbox matches the nspawn instance
# it replaces.
#
# This image is amd64-only and can only ever schedule on the dedicated amd64
# `sandbox-node` (the RuntimeClass nodeSelector pins it). The cluster's usual
# arm64 requirement is a deliberate, node-scoped exception for this workload.
#
# Build:
#   docker build --platform linux/amd64 -t ghcr.io/myles-coleman/opencode-sandbox:v2.0.23 .
#   docker push ghcr.io/myles-coleman/opencode-sandbox:v2.0.23
#
# Then pin the digest in manifests/cluster/agent-sandbox/sandbox.yaml.
#
# Edit-only: there is NO Nix in this image. The nspawn instance could `nix build`
# because it bind-mounted the host /nix/store and the Nix daemon socket; neither
# is possible in a Kubernetes gVisor pod. The agent edits files and the operator
# (or CI) builds. See ./AGENTS.md, which overrides the repo's own AGENTS.md.

FROM --platform=linux/amd64 debian:bookworm-slim

ARG OPENCODE_VERSION=2.0.23
# Confirm the release asset name/URL for the pinned version before building; the
# upstream project publishes platform tarballs on GitHub releases.
ARG OPENCODE_ASSET_URL=https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.zip

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils curl git ripgrep tar unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/opencode.zip "$OPENCODE_ASSET_URL" \
    && unzip -q /tmp/opencode.zip -d /usr/local/bin \
    && rm -f /tmp/opencode.zip \
    && chmod +x /usr/local/bin/opencode \
    && opencode --version

# Unprivileged user; the workspace and $HOME live on a Retain PVC mounted here.
# fsGroup is ignored on local/hostPath volumes, so the owner is set explicitly.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent
USER 1000:1000
WORKDIR /home/agent

# The OpenCode server port (the pod's Service and the tailnet operator path use it).
EXPOSE 4096

ENTRYPOINT ["opencode"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "4096"]
