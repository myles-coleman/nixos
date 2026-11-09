{
  config,
  pkgs,
  lib,
  ...
}: {
  # Docker
  virtualisation.docker.enable = true;

  # This host egresses through a tailscale exit node, so `tailscale0` is MTU
  # 1280 while Docker's default bridge is 1500. The mismatch is a silent PMTU
  # blackhole: containers connect fine, then any response over a few hundred
  # bytes never arrives. It broke `apt-get update` and model downloads inside
  # the transcriber container (2026-11-09) with no diagnostic beyond "Ign:".
  # Match the bridge to the egress MTU.
  virtualisation.docker.daemon.settings.mtu = 1280;

  # Declarative Docker containers for this host live in host-local modules:
  #   - ./strata.nix — the Strata model backend (spec 20, Unit 1)
  #
  # The `qwen-177b` llama.cpp container was removed when Strata replaced it as the
  # fleet's single model backend (spec 20); there is one model server, not two, so
  # there is no duplicate 80 GB model copy and no VRAM contention.
}
