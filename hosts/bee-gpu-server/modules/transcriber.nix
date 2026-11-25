{
  config,
  pkgs,
  lib,
  ...
}: let
  # Persistent state: downloaded ggml models (~1.7 GB for turbo + large-v3 + VAD)
  # and one directory per job. Never tmpfs: a model re-download is minutes of
  # bandwidth and a job directory holds the only copy of a transcript.
  dataDir = "/var/lib/transcriber";

  # Matches `bee` on the host and the uid the image is built with.
  runtimeUid = 1000;
  runtimeGid = config.users.groups.render.gid;

  port = 8090;

  # Digest-pinned PUBLIC GHCR image. Built from ~/transcript-tool's Dockerfile;
  # pin the digest after `docker push` (the tag can move, the digest cannot).
  image = "ghcr.io/myles-coleman/transcript-tool@sha256:f8cb77a1eb79ca9898a2bf61972693c5869e3d08eed4a0b97741911a4430591b";

  # 12 cores, but Strata shares this box and the GPU is the bottleneck anyway.
  threads = "8";
in {
  # Same backend as Strata. `mkDefault` because strata.nix already states it and
  # the oci-containers default (podman) would otherwise win.
  virtualisation.oci-containers.backend = lib.mkDefault "docker";

  virtualisation.oci-containers.containers.transcriber = {
    inherit image;

    # Loopback only. The tailnet reaches it through `tailscale serve` below,
    # which terminates TLS on the MagicDNS name; nothing else can connect.
    # Docker's published ports bypass the host firewall, so this is the bind
    # address doing the work, not a firewall rule.
    ports = ["127.0.0.1:${toString port}:8090/tcp"];

    volumes = ["${dataDir}:/data"];

    environment = {
      WHISPER_THREADS = threads;
      # large-v3-turbo for English, large-v3 for non-English -> English.
      # turbo cannot translate: it silently returns the source language.
      DEFAULT_MODEL = "large-v3-turbo";
      TRANSLATE_MODEL = "large-v3";
      PORT = "8090";

      # Summaries are generated here, not on the client: the transcript and the
      # model's API key both stay on this host. Strata serves on the same
      # machine, and `strata-port-guard` exempts the docker bridge for exactly
      # this call.
      STRATA_URL = "http://100.127.170.8:8080/v1";
      STRATA_MODEL = "qwen3.8-flash-next";
    };

    # The key is injected by the daemon from the file that already exists for
    # Strata (root-owned, 0400), so it is never written into this repository, the
    # Nix store, or `docker run --env` argv. The environment file names it
    # API_KEY; app/summarize.py accepts either that or STRATA_API_KEY.
    environmentFiles = ["/run/strata/strata.env"];

    extraOptions = [
      # Vulkan needs the render node; Mesa RADV lives inside the image.
      "--device=/dev/dri/renderD128"
      # Numeric GIDs: Docker resolves names against the *container's* /etc/group.
      "--group-add=${toString config.users.groups.video.gid}"
      "--group-add=${toString runtimeGid}"
      "--user=${toString runtimeUid}:${toString runtimeGid}"
      # A cancelled transcription should not linger holding the card.
      "--stop-timeout=30"
    ];
  };

  # The container reaches Strata through the host's published port, and that
  # path lands on the INPUT chain, which the firewall drops. Without this the
  # summarize call hangs until it times out — the DOCKER-USER guard is not
  # involved, because docker-proxy answers on the host, not by forwarding.
  networking.firewall.interfaces."docker0".allowedTCPPorts = [8080];

  # HTTPS on the tailnet's own DNS name, with a certificate Tailscale issues
  # and renews: https://bee-gpu-server.tail6d2e9b.ts.net
  #
  # nixpkgs' tailscale module has no `serve` option, so the state is asserted by
  # a oneshot. `--bg` persists the config in tailscaled, which is why this is
  # safe to run once per boot rather than as a long-lived proxy process.
  systemd.services.tailscale-serve-transcriber = {
    description = "Publish the transcriber on the tailnet over HTTPS";
    wantedBy = ["multi-user.target"];
    wants = ["tailscaled.service" "docker-transcriber.service"];
    after = ["tailscaled.service" "docker-transcriber.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${config.services.tailscale.package}/bin/tailscale serve --bg ${toString port}
    '';
  };

  # `environmentFiles` is read when the container starts, so the file has to
  # exist by then. `strata-env` renders it; a plain `after` avoids making the
  # transcriber restart whenever the key rotates.
  systemd.services.docker-transcriber = {
    after = ["strata-env.service"];
    wants = ["strata-env.service"];
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${toString runtimeUid} ${toString runtimeGid} -"
  ];
}
