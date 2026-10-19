# syntax=docker/dockerfile:1
#
# Allowlisting forward proxy for the agent sandbox (spec 20, Unit 3).
#
# WHY NOT `ubuntu/squid`: that image ships Ubuntu's default squid, which is built
# with GnuTLS and does NOT support the SSL-bump ACLs this policy needs — the
# binary contains neither `at_step` nor `ssl::server_name`, so a peek-then-splice
# config fails with "invalid ACL type". Ubuntu publishes the OpenSSL build as the
# separate `squid-openssl` package (`--with-openssl`); this image installs it.
#
# Multi-arch on purpose: squid is an ordinary cluster Deployment with no node
# pinning, and the worker nodes are arm64 while the amd64 sandbox node is the only
# x86_64 host. The Dockerfile is platform-neutral; build with
# `--platform linux/amd64,linux/arm64`.
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t ghcr.io/myles-coleman/squid:6.14 --push .
#
# Then pin the digest in ~/homelab-cluster/manifests/cluster/squid/deployment.yaml.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        squid-openssl \
        ca-certificates \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && squid -v | head -1

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Foreground, no daemon, and the mounted config. `-C` skips the (unused) on-disk
# cache; `-Y` keeps squid running if a cache_dir is unavailable.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["-f", "/etc/squid/squid.conf", "-NYC"]

EXPOSE 3128
