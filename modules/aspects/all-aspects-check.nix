{
  config,
  inputs,
  lib,
  ...
}: {
  # deferredModule values are lazy, so an aspect that no host lists is never
  # evaluated. This synthetic check forces every registered NixOS and Home
  # Manager aspect through a minimal dummy configuration so type/option errors
  # surface even for unlisted aspects. Evaluation-only (no build).
  flake.checks = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system:
    lib.genAttrs ["all-aspects"] (_: let
      nixpkgs = inputs.nixpkgs;
      nixosAspects = builtins.attrValues config.flake.modules.nixos;
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
