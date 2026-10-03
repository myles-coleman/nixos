{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.cli-extras.enable = lib.mkEnableOption "extra CLI tooling (wget, fastfetch, gnumake, ranger)";

  config = lib.mkIf config.my.roles.cli-extras.enable {
    environment.systemPackages = with pkgs; [
      wget
      fastfetch
      gnumake
      ranger
    ];
  };
}
