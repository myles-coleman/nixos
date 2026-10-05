{config, ...}: {
  # `services.tailscale` invariants shared across hosts. Hosts that need
  # `useRoutingFeatures`, `authKeyFile`, or extra flags keep those host-local
  # (they are scalars/lists that would conflict if shared). Composes `unstable`
  # so `pkgs.unstable` resolves.
  flake.modules.nixos.tailscale = {pkgs, ...}: {
    imports = [config.flake.modules.nixos.unstable];

    services.tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      openFirewall = true;
    };
  };
}
