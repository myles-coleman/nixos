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
# CI builds and pushes this image from .github/workflows/build-images.yaml, and
# runs ./check-tools.sh against the built image BEFORE the push (spec 30,
# FR-56 / FR-57). A version drift therefore fails the build, not production.
#
# Digest repin procedure (FR-56):
#   1. Merge to `main`; `.github/workflows/build-images.yaml` builds this image,
#      verifies the toolchain, pushes it, and prints `image@sha256:...` in the
#      run summary.
#   2. Copy that digest into `manifests/cluster/agent-sandbox/sandbox.yaml` in
#      `homelab-cluster`.
#   3. Recreate the Sandbox Pod. The Agent Sandbox controller does not replace an
#      existing Pod when the template changes, so delete the Pod and let the
#      controller create a new one from the repinned template.
#
# Edit-only: there is NO Nix in this image. The nspawn instance could `nix build`
# because it bind-mounted the host /nix/store and the Nix daemon socket; neither
# is possible in a Kubernetes gVisor pod. The agent edits files and the operator
# (or CI) builds. See ./AGENTS.md, which overrides the repo's own AGENTS.md.

# statix and deadnix publish no linux binary at the pinned versions, and the
# crates.io entries are not the upstream tools at these versions. Build both
# from the tagged upstream sources in a throwaway stage and copy only the two
# executables. `--locked` uses each repository's committed Cargo.lock.
FROM rust:1.89.0-bookworm AS rustbuild

ARG STATIX_VERSION=0.5.8
ARG DEADNIX_VERSION=1.3.2

RUN cargo install --locked --root /out \
        --git https://github.com/oppiliappan/statix --tag "v${STATIX_VERSION}" \
    && cargo install --locked --root /out \
        --git https://github.com/astro/deadnix --tag "v${DEADNIX_VERSION}"

FROM --platform=linux/amd64 node:22-bookworm-slim

ARG OPENCODE_VERSION=2.0.23

# Debian package pins (spec 30, FR-56). These are exact archive versions, so a
# bookworm point release that respins git or curl makes the apt-get install fail
# closed instead of silently drifting to whatever the base image carries. To
# move to a respin, update the two ARGs here AND the matching defaults in
# ./check-tools.sh in the same change.
ARG GIT_VERSION=2.39.5-0+deb12u3
ARG CURL_VERSION=7.88.1-10+deb12u15

# Upstream release pins. Each digest is verified against the project's own
# checksum file and then against the literal below before anything is installed.
ARG JQ_VERSION=1.8.2
ARG JQ_SHA256=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
ARG ALEJANDRA_VERSION=4.1.0
ARG ALEJANDRA_SHA256=1f977b58dabc146d1f1c872272b5c3136b9f3152b41bc91a60ec2ad4eb3f70ad
ARG KUSTOMIZE_VERSION=5.8.3
ARG KUSTOMIZE_SHA256=cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61
ARG HELM_VERSION=4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ARG KUBECONFORM_VERSION=0.8.0
ARG KUBECONFORM_SHA256=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883

# Prompt/lint dependencies for the Python venv. Pinned with the linter so the
# image is reproducible.
ARG YAMLLINT_VERSION=1.38.0
ARG PYYAML_VERSION=6.0.2
ARG PATHSPEC_VERSION=1.1.1

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils curl="${CURL_VERSION}" git="1:${GIT_VERSION}" \
        ripgrep tar unzip \
        python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# jq — static binary; verify against the release sha256sum.txt.
RUN set -eux; \
    base="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}"; \
    curl -fsSL -o /tmp/jq "${base}/jq-linux-amd64"; \
    curl -fsSL -o /tmp/jq.sha256sum.txt "${base}/sha256sum.txt"; \
    grep -Fq "${JQ_SHA256}" /tmp/jq.sha256sum.txt; \
    printf '%s  %s\n' "${JQ_SHA256}" /tmp/jq | sha256sum -c -; \
    install -m 0755 /tmp/jq /usr/local/bin/jq; \
    rm -f /tmp/jq /tmp/jq.sha256sum.txt

# alejandra — musl binary; verify against the release SHA256SUMS.
RUN set -eux; \
    base="https://github.com/kamadorueda/alejandra/releases/download/${ALEJANDRA_VERSION}"; \
    curl -fsSL -o /tmp/alejandra "${base}/alejandra-x86_64-unknown-linux-musl"; \
    curl -fsSL -o /tmp/alejandra.SHA256SUMS "${base}/SHA256SUMS"; \
    grep -Fq "${ALEJANDRA_SHA256}" /tmp/alejandra.SHA256SUMS; \
    printf '%s  %s\n' "${ALEJANDRA_SHA256}" /tmp/alejandra | sha256sum -c -; \
    install -m 0755 /tmp/alejandra /usr/local/bin/alejandra; \
    rm -f /tmp/alejandra /tmp/alejandra.SHA256SUMS

# kustomize — tarball; verify against the release checksums.txt.
RUN set -eux; \
    base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"; \
    curl -fsSL -o /tmp/kustomize.tar.gz "${base}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"; \
    curl -fsSL -o /tmp/kustomize.checksums.txt "${base}/checksums.txt"; \
    grep -Fq "${KUSTOMIZE_SHA256}" /tmp/kustomize.checksums.txt; \
    printf '%s  %s\n' "${KUSTOMIZE_SHA256}" /tmp/kustomize.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/kustomize.tar.gz -C /usr/local/bin kustomize; \
    chmod 0755 /usr/local/bin/kustomize; \
    rm -f /tmp/kustomize.tar.gz /tmp/kustomize.checksums.txt

# helm — tarball; verify against the published .sha256sum.
RUN set -eux; \
    base="https://get.helm.sh"; \
    curl -fsSL -o /tmp/helm.tar.gz "${base}/helm-v${HELM_VERSION}-linux-amd64.tar.gz"; \
    curl -fsSL -o /tmp/helm.sha256sum "${base}/helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"; \
    grep -Fq "${HELM_SHA256}" /tmp/helm.sha256sum; \
    printf '%s  %s\n' "${HELM_SHA256}" /tmp/helm.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/helm.tar.gz -C /tmp linux-amd64/helm; \
    install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/helm.sha256sum /tmp/linux-amd64

# kubeconform — tarball; verify against the release CHECKSUMS.
RUN set -eux; \
    base="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}"; \
    curl -fsSL -o /tmp/kubeconform.tar.gz "${base}/kubeconform-linux-amd64.tar.gz"; \
    curl -fsSL -o /tmp/kubeconform.CHECKSUMS "${base}/CHECKSUMS"; \
    grep -Fq "${KUBECONFORM_SHA256}" /tmp/kubeconform.CHECKSUMS; \
    printf '%s  %s\n' "${KUBECONFORM_SHA256}" /tmp/kubeconform.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/kubeconform.tar.gz -C /usr/local/bin kubeconform; \
    chmod 0755 /usr/local/bin/kubeconform; \
    rm -f /tmp/kubeconform.tar.gz /tmp/kubeconform.CHECKSUMS

# statix + deadnix — built in the rustbuild stage above.
COPY --from=rustbuild /out/bin/statix /usr/local/bin/statix
COPY --from=rustbuild /out/bin/deadnix /usr/local/bin/deadnix

# yamllint — isolated venv so its Python deps cannot disturb the base image.
RUN python3 -m venv /opt/yamllint \
    && /opt/yamllint/bin/pip install --no-cache-dir \
        "yamllint==${YAMLLINT_VERSION}" \
        "PyYAML==${PYYAML_VERSION}" \
        "pathspec==${PATHSPEC_VERSION}" \
    && ln -s /opt/yamllint/bin/yamllint /usr/local/bin/yamllint

# The toolchain check that CI runs before the push, and that an operator can run
# with `docker run --rm <image> /opt/sandbox/check-tools.sh`.
COPY check-tools.sh /opt/sandbox/check-tools.sh
RUN chmod 0755 /opt/sandbox/check-tools.sh

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
