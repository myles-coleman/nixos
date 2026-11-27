{inputs, ...}: {
  # Brave for the two desktop hosts (bee-pc, bee-gpd).
  #
  # Brave is fetched from a dedicated nixpkgs pin (`nixpkgs-brave`, see flake.nix)
  # instead of the system channel. nixpkgs dropped brave/brave-origin in
  # PR #582838/#582874 (2026-11-03) because none of the package's maintainers
  # were committers, and re-added them in PR #584534 (2026-11-07) once that was
  # fixed. The separate pin means a future removal or a slow backport cannot
  # break evaluation here, and `nix flake update nixpkgs-brave` bumps only the
  # browser.
  flake.modules.nixos.brave = {pkgs, ...}: {
    nixpkgs.overlays = [
      (final: _prev: {
        # `legacyPackages` cannot carry `config`, and brave is unfree, so import
        # the pinned nixpkgs the same way the `unstable` aspect does.
        brave =
          (import inputs.nixpkgs-brave {
            system = final.system;
            config.allowUnfree = true;
          }).brave;
      })
    ];

    environment.systemPackages = with pkgs; [brave];
  };
}
