{
  config,
  inputs,
  lib,
  ...
}: {
  # deferredModule values are lazy, so an aspect that no host lists is never
  # evaluated. This synthetic check forces every registered aspect through a
  # minimal dummy configuration so type/option errors surface even for unlisted
  # aspects. Evaluation-only (no build).
  #
  # The shared x86_64 aspects (desktop/gaming/dev-tools/common) are x86-only:
  # `programs.steam` pulls i686 packages and `boot.binfmt.emulatedSystems` is
  # cross-arch, so they are only type-checked against x86_64. The Home Manager
  # aspects are architecture-neutral and are checked on both systems.
  flake.checks = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system:
    lib.genAttrs ["all-aspects"] (_: let
      nixpkgs = inputs.nixpkgs;
      # Host aspects are full NixOS configurations (they set boot/loader and
      # other concrete host options) and must not be merged into the dummy
      # config. Only shared aspects are type-checked here.
      hostAspectNames = ["homelab" "bee-pc" "bee-gpd" "bee-gpu-server" "protecli-vault"];
      nixosAspects =
        if system == "x86_64-linux"
        then builtins.attrValues (builtins.removeAttrs config.flake.modules.nixos hostAspectNames)
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
