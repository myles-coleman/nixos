{
  config,
  pkgs,
  lib,
  ...
}: let
  # ── The single swappable model value (spec 20, Unit 1) ───────────────────────
  #
  # The quantization is a first-class, swappable config value — NOT a build-time
  # choice. The engine is compiled per *card* (gfx1100), not per quant, and the
  # model lives on the persistent /data volume, so a swap is: change `modelQuant`
  # here, restart the container. No image rebuild, no engine recompile.
  #
  # See the runbook's "Quant swap" procedure: set the value; check the new quant's
  # VRAM/RAM requirement against what is free with KDE running; restart with a
  # generous --stop-timeout; confirm /health and /v1/models before re-enabling
  # traffic. Expect to re-tune `contextLength` and the resident budget.
  modelQuant = "IQ2_XS";
  modelFamily = "qwen";

  # The served alias. STABLE across quant swaps so consumers (the sandbox,
  # open-webui, mastra, bee-gpd) never learn which quant is behind it. Strata has
  # no --alias flag; the alias lives in the config's `aliases` list, which the
  # entrypoint's setup writes. This name must not change when `modelQuant` changes.
  modelAlias = "qwen3.8-flash-next";

  # ~68 GB model + ~10 GB ROCm venv + the per-card engine build live here, so a
  # restart or an image change does not cost a 10-20 minute recompile plus a
  # re-download.
  dataDir = "/home/bee/strata";

  # Digest-pinned PUBLIC GHCR image (built from ./images/strata-rocm/Dockerfile),
  # so no pull credential is needed on the host.
  #
  # Built from Strata tag v0.1.45 (commit 477ac13) with HIP_ARCHITECTURES=gfx1100;
  # engine/BUILD.json inside the image reads source=local-hip, backend=hip.
  image = "ghcr.io/myles-coleman/strata-rocm@sha256:3e126d5eeac41c687decc05147fd5bec9ef9676b5bb1c4008db0b35dfbd1a521";

  apiKeySecret = "strata_api_key";
in {
  # The host's containers run on Docker. This must be set explicitly: the
  # oci-containers default is `podman` for stateVersion >= 22.05, which names the
  # unit `podman-strata.service` and breaks the sops `restartUnits` wiring (and
  # would run a second container runtime alongside the host's Docker).
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.strata = {
    inherit image;

    ports = ["8080:8080/tcp"];

    volumes = ["${dataDir}:/data"];

    # The GHCR package is PUBLIC, so no pull credential is needed. (A public
    # package removes a whole credential from the host; the image contains only
    # our build of an open-source project.)

    # Model settings. `MODEL` is the swappable quant value; `API_KEY` is NOT set
    # here (it would land in the Nix store and in `docker run --env` argv) — it is
    # injected via the environment file rendered in `strata-env` below.
    environment = {
      FAMILY = modelFamily;
      MODEL = modelQuant;
      CONTEXT = "100000";
      # The AMD backend has no GPU image encoder; the sandbox does not need vision.
      VISION = "no";
      KV = "int8";
      GPU = "0";
      LOW_RAM = "auto";
      HOST = "0.0.0.0";
      PORT = "8080";
      # Keep KDE Plasma (which shares the 7900 XTX) from being OOM-killed by the
      # expert cache. Strata's documented AMD-desktop fix; the default reserve is
      # 700 MiB. Confirm the entrypoint consumes this env var (Phase 3).
      VRAM_RESERVE_MIB = "3072";
    };

    # The API key arrives as `API_KEY=<secret>` from a root-only file rendered at
    # container start, so it never appears in argv, the environment of the Nix
    # build, or a committed file.
    environmentFiles = ["/run/strata/strata.env"];

    extraOptions = [
      # The flags the host's existing llama.cpp container already proves work on
      # this card.
      "--device=/dev/kfd"
      "--device=/dev/dri/renderD128"
      # Numeric GIDs, not names: Docker resolves `--group-add <name>` against the
      # *container's* /etc/group, and the Ubuntu-based Strata image has no
      # `render`/`video` entries, so the names fail with "no matching entries in
      # group file". These GIDs come from NixOS's own group definitions. (The
      # container runs as root, so these are belt-and-braces for the devices.)
      "--group-add=${toString config.users.groups.video.gid}"
      "--group-add=${toString config.users.groups.render.gid}"
      "--ipc=host"
      "--security-opt=seccomp=unconfined"
      "--ulimit=memlock=-1"
      # SIGTERM releases tens of GB of page-locked RAM; give it time so the next
      # quant can allocate.
      "--stop-timeout=120"
    ];
  };

  # ── Secrets ──────────────────────────────────────────────────────────────────
  # The Strata API key lives in secrets/hosts/bee-gpu-server.yaml (see .sops.yaml).
  # A rotation restarts the container so the new credential is picked up. No GHCR
  # credential is needed: the image package is public.
  sops.secrets.${apiKeySecret} = {
    owner = "root";
    mode = "0400";
    restartUnits = ["docker-strata.service"];
  };

  # Render the container environment file from the decrypted API key. `partOf`
  # ties it to the container's lifecycle so a secret rotation (which restarts
  # docker-strata) re-renders the file before the container starts again.
  systemd.services.strata-env = {
    description = "Render the Strata container environment file from sops";
    wantedBy = ["docker-strata.service"];
    before = ["docker-strata.service"];
    after = ["sops-install-secrets.service"];
    requires = ["sops-install-secrets.service"];
    partOf = ["docker-strata.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "strata";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      umask 077
      printf 'API_KEY=%s\n' "$(cat ${config.sops.secrets.${apiKeySecret}.path})" \
        > /run/strata/strata.env
    '';
  };

  # The model files and engine build live on the NVMe under dataDir.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root -"
  ];
}
