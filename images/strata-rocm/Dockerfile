# syntax=docker/dockerfile:1
#
# Strata ROCm image for bee-gpu-server's AMD Radeon RX 7900 XTX (gfx1100, RDNA3).
#
# Vendored recipe: this is our authored, auditable thin image, based on the recipe
# in upstream PR Niko1221/Strata#1486 ("Dockerfile.rocm-stable"). The upstream
# Dockerfile in the repo is CUDA-only and there is no first-party ROCm image, so an
# authored image is required. We vendor the *recipe* rather than the PR's file so the
# ROCm/hipBLASLt pairing stays under our control. See ./README.md for provenance.
#
# What it does, and why:
#   - plain Ubuntu base; no ROCm base image. setup.py's HIP path (build_engine_hip)
#     installs AMD's TheRock ROCm wheels (~10 GB) into .venv when /opt/rocm has no
#     system ROCm 7.
#   - the engine is compiled during the build, per *card* (HIP_ARCHITECTURES=gfx1100),
#     NOT per quantization. That is why swapping the quant later costs one config value
#     and a restart, with no rebuild and no recompile.
#   - upstream's docker-entrypoint.sh is reused verbatim (COPY . . pulls it in).
#
# Build (the build context is a checkout of the Strata repo with this file overlaid):
#   git clone https://github.com/Niko1221/Strata strata && cd strata
#   git checkout <pinned-commit>
#   cp /path/to/images/strata-rocm/Dockerfile Dockerfile
#   docker build -t ghcr.io/myles-coleman/strata-rocm:gfx1100 .
#   docker push ghcr.io/myles-coleman/strata-rocm:gfx1100
#
# Then pin the resulting digest in hosts/bee-gpu-server/modules/strata.nix.

FROM ubuntu:24.04

# STRATA_EXECV=1: setup.py replaces itself with the server, so the server is PID 1 and
# `docker stop`'s SIGTERM reaches it. SIGTERM releases tens of GB of page-locked RAM,
# which is why the container is run with a generous --stop-timeout (see strata.nix).
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 LANG=C.UTF-8 STRATA_EXECV=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git libatomic1 libgomp1 \
        python3 python3-pip python3-venv unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/strata
COPY . .

# The single card this image targets. Narrowing to gfx1100 (RX 7900 XTX) keeps the
# build fast; a different card needs a rebuild with its own arch. BUILD_VISION=0 skips
# the image encoder build (the AMD backend has no GPU image encoder yet).
ARG HIP_ARCHITECTURES=gfx1100
ARG BUILD_VISION=0

RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir --upgrade pip \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt \
    && chmod +x setup.sh docker-entrypoint.sh

# llama.cpp at the pinned commit, then the HIP engine, built exactly the way setup.py
# builds it on a Linux PC. docker build has no GPU to probe, so the card dict comes
# from HIP_ARCHITECTURES instead of a device probe. BUILD.json is what setup.py reads
# to decide whether an engine is current, so the first start reuses it instead of
# recompiling (10-20 minutes).
RUN .venv/bin/python - <<'PYEOF'
import os
import setup

llama = setup.get_llama_cpp()
archs = [a for a in os.environ.get("HIP_ARCHITECTURES", "gfx1100").replace(",", ";").split(";") if a]
vision = "cpu" if os.environ.get("BUILD_VISION", "0") == "1" else "none"

gpu = {"index": 0, "name": "AMD (from HIP_ARCHITECTURES)", "vram_gb": 24.0,
       "arch": archs[0], "archs": archs, "driver": "hip", "vendor": "amd"}
setup.build_engine_hip(gpu, llama, vision)
PYEOF

# the cmake trees are build-time only; the engine itself is what the container needs
RUN rm -rf build-hip build-vision

# Only the model files, the prepared pack, the MTP layer and the install config live in
# /data; the engine is part of the image.
VOLUME ["/data"]
EXPOSE 8080

# /health is answered before the API key gate, so it works with or without one. The port
# only opens after the model loads (1-3 minutes, longer on a first run), so the start
# period is generous.
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD curl -fs "http://127.0.0.1:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
