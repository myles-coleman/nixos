{inputs, ...}: {
  flake.modules.nixos.unstable = {config, ...}: {
    nixpkgs.overlays = [
      (final: _prev: {
        unstable = import inputs.nixpkgs-unstable {
          system = final.system;
          config.allowUnfree = true;
        };
      })
    ];
  };
}
