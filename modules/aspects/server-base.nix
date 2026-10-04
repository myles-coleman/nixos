{
  flake.modules.nixos.server-base = {pkgs, ...}: {
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
