{
  config,
  inputs,
  lib,
  ...
}: {
  # deferredModule values are lazy, so an aspect that no host lists is never
  # evaluated. This synthetic check forces the shared x86_64 aspects through a
  # minimal dummy configuration so type/option errors surface even for unlisted
  # aspects. Evaluation-only (no build).
  #
  # Selection is an EXPLICIT x86-only allowlist, not a "remove known host
  # aspects" heuristic: the RPi aspects (spec 16) are aarch64-only, depend on
  # vendor board modules via `specialArgs`, and some set mutually-exclusive k3s
  # roles or require `end0`/gateway, so they cannot be merged into this x86
  # dummy. An allowlist means registering new aarch64/aspect names can never
  # leak into this check. The RPi aspects are guarded by the `build-arm` lane,
  # which builds every RPi host that lists them.
  #
  # The Home Manager aspects are architecture-neutral and are checked on both
  # systems.
  flake.checks = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system:
    lib.genAttrs ["all-aspects"] (_: let
      nixpkgs = inputs.nixpkgs;
      # Explicit x86-only allowlist. Keep this list in sync when a new shared
      # x86 aspect is added; aarch64/RPi aspects intentionally do not appear.
      x86AspectNames = [
        "common"
        "desktop"
        "dev-tools"
        "gaming"
        "home-desktop"
        "home-zsh"
        "network"
        "nvidia"
        "cli-core"
        "cli-extras"
        "server-base"
        "k8s"
        "unstable"
      ];
      nixosAspects =
        if system == "x86_64-linux"
        then
          map (n: config.flake.modules.nixos.${n})
          (builtins.filter (n: builtins.hasAttr n config.flake.modules.nixos) x86AspectNames)
        else [];
      hmAspects = builtins.attrValues config.flake.modules.homeManager;
      base = nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          [
            {
              nixpkgs.hostPlatform = system;
              system.stateVersion = "25.05";
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "/dev/null";
                fsType = "ext4";
              };
              users.users.bee.isNormalUser = true;
            }
            inputs.home-manager.nixosModules.default
          ]
          ++ nixosAspects;
      };
      hmBase = nixpkgs.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules =
          [
            {home.username = "bee";}
            {home.homeDirectory = "/home/bee";}
            {home.stateVersion = "25.05";}
          ]
          ++ hmAspects;
      };
    in {
      type = "derivation";
      name = "all-aspects-${system}";
      inherit (base.config.system.build.toplevel) drvPath;
      hmDrvPath = hmBase.activationPackage.drvPath;
    }));
}
