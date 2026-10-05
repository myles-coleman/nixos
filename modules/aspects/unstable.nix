{inputs, ...}: {
  flake.modules.nixos.unstable = {config, ...}: {
    nixpkgs.overlays = [
      (final: _prev: {
        unstable = import inputs.nixpkgs-unstable {
          system = final.system;
          config.allowUnfree = true;
        };
        # opencode v2, pinned to a v2 tag via the flake input.
        opencodeV2 = inputs.opencodeV2.packages.${final.system}.default;
      })
    ];
  };
}
