# `images/strata-rocm/` — authored Strata ROCm image

This directory holds the authored Dockerfile for the Strata inference engine on
`bee-gpu-server`'s AMD Radeon RX 7900 XTX (gfx1100). It is the image that replaces
the `qwen-177b` llama.cpp container as the fleet's single model backend (spec 20,
Unit 1).

## Why an authored image

- Upstream `Niko1221/Strata` ships a **CUDA-only** `Dockerfile` and a CUDA-only
  `flake.nix`; there is **no first-party ROCm image**.
- A public unofficial ROCm image exists (`ghcr.io/selfref/strata-rocm`, gfx1100/1101/1102),
  but it is a single-maintainer build with a build-only, GPU-less CI. Running its
  binaries with `/dev/kfd` access and tens of GB of `mlock` is a supply-chain bet
  not worth taking to save ~40 lines.
- Upstream PR **#1486** ("`Dockerfile.rocm-stable`", open/unmerged at the time of
  writing) provides the recipe. We vendor the **recipe**, not the file, so the
  ROCm/hipBLASLt pairing stays under our control.

## Provenance

| Item | Value |
| --- | --- |
| Upstream repo | `https://github.com/Niko1221/Strata` |
| Recipe source | PR #1486, file `Dockerfile.rocm-stable` |
| Vendored on | 2026-10-17 |
| Engine build path | `setup.py` → `build_engine_hip(gpu, llama, vision)` (TheRock ROCm wheels into `.venv`) |
| Entrypoint | upstream `docker-entrypoint.sh`, reused verbatim (`COPY . .`) |

Pin the upstream checkout to a recorded commit at build time (the engine is a
fast-moving, no-CI project). Record that commit here when the image is built:

| Item | Value |
| --- | --- |
| Strata commit built | `477ac13cbe8e582c20484871ce459d20d82df09d` (tag `v0.1.45`) |
| Engine build | `source: local-hip`, `backend: hip`, `archs: [gfx1100]`, `vision: none` (from `engine/BUILD.json`) |
| ROCm pairing | TheRock `rocm[libraries,devel]==7.10.0a20251120` (the wheels `setup.py` pins; the engine refuses a mismatched hipBLASLt table) |
| Published image digest | `ghcr.io/myles-coleman/strata-rocm@sha256:…` — pinned in `hosts/bee-gpu-server/modules/strata.nix` |

## Build gotcha on `bee-gpu-server`

The host resolves `archive.ubuntu.com` to **IPv6**, and Docker's default bridge network has no
IPv6, so `apt-get update` inside the build silently `Ign`ores every repo and hangs. Build with the
host network:

```bash
docker build --network=host -t ghcr.io/myles-coleman/strata-rocm:gfx1100 .
```

**Do not clone the build context into the data volume.** `/home/bee/strata` on `bee-gpu-server` is
the container's `/data` (created `0700 root` by tmpfiles). Clone to a scratch path instead, e.g.
`/var/tmp/strata-build` — cloning into the data dir collides with it and leaves the whole source tree
inside the volume.

The package is **public**, so the host pulls it anonymously — there is no pull credential to
provision.

## Build

The build context is a checkout of the Strata repo with this Dockerfile overlaid:

```bash
git clone https://github.com/Niko1221/Strata strata && cd strata
git checkout <pinned-commit>
cp /path/to/nixos/images/strata-rocm/Dockerfile Dockerfile
docker build -t ghcr.io/myles-coleman/strata-rocm:gfx1100 .
docker push ghcr.io/myles-coleman/strata-rocm:gfx1100
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/myles-coleman/strata-rocm:gfx1100
```

Then set the digest in `hosts/bee-gpu-server/modules/strata.nix`.

## Notes

- The engine is compiled per **card** (`gfx1100`), not per quantization, so a quant
  swap is one config value plus a container restart — no rebuild, no recompile.
- `BUILD_VISION=0` skips the image encoder: the AMD backend has no GPU image encoder
  yet, and the sandbox does not need vision.
- The image cannot be built in the Nix sandbox.
