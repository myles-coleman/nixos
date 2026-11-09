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
  image = "ghcr.io/myles-coleman/transcript-tool@sha256:766dd0fc057833aa19393daf9efc62c5a49e278015e109c495879ce2d074b6af";

  # 12 cores, but Strata shares this box and the GPU is the bottleneck anyway.
  threads = "8";
in {
  # Same backend as Strata. `mkDefault` because strata.nix already states it and
  # the oci-containers default (podman) would otherwise win.
  virtualisation.oci-containers.backend = lib.mkDefault "docker";

  virtualisation.oci-containers.containers.transcriber = {
    inherit image;

    # Tailnet-only on purpose. Docker publishes ports by inserting its own
    # iptables rules, which bypass the host firewall, so binding to 0.0.0.0
    # would expose transcripts to the whole LAN. Pinning the published address
    # to the tailscale IP is the same pattern Strata uses (100.127.170.8:8080).
    ports = ["100.127.170.8:${toString port}:8090/tcp"];

    volumes = ["${dataDir}:/data"];

    environment = {
      WHISPER_THREADS = threads;
      # large-v3-turbo for English, large-v3 for non-English -> English.
      # turbo cannot translate: it silently returns the source language.
      DEFAULT_MODEL = "large-v3-turbo";
      TRANSLATE_MODEL = "large-v3";
      PORT = "8090";
    };

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

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${toString runtimeUid} ${toString runtimeGid} -"
  ];
}
