{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.users.${mainUser} = {
    services.gammastep = {
      enable = true;
      provider = "manual";
      latitude = 37.7749;
      longitude = -122.4194;
      temperature = {
        day = 5500;
        night = 3500;
      };
      settings = {
        general = {
          brightness-day = "1.0";
          brightness-night = "0.8";
        };
      };
    };

    xdg.configFile = {
      "hypr/hyprland.conf".source = ./hyprland.conf;
      "hypr/start.sh" = {
        source = ./start.sh;
        executable = true;
      };
      "waybar/kvm-switch.sh" = {
        source = ../../../config/waybar/kvm-switch.sh;
        executable = true;
      };
    };
  };
}
