{
  config,
  pkgs,
  lib,
  ...
}: {
  # Docker
  virtualisation.docker.enable = true;

  # Declarative Docker containers for this host live in host-local modules:
  #   - ./strata.nix — the Strata model backend (spec 20, Unit 1)
  #
  # The `qwen-177b` llama.cpp container was removed when Strata replaced it as the
  # fleet's single model backend (spec 20); there is one model server, not two, so
  # there is no duplicate 80 GB model copy and no VRAM contention.
}
