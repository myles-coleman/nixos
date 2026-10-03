{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.server-base.enable = lib.mkEnableOption "shared server tooling (git, curl, tldr, gcc, gnupg, lm_sensors)";

  config = lib.mkIf config.my.roles.server-base.enable {
    environment.systemPackages = with pkgs; [
      git
      curl
      tldr
      gcc
      gnupg
      lm_sensors
    ];
  };
}
