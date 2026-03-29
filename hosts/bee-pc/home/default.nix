{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.users.${mainUser} = {
    services.hyprpaper = {
      enable = true;
      settings = {
        ipc = "on";
        splash = false;
        preload = [
          "~/.config/wallpaper1.jpg"
        ];
        wallpaper = [
          "DP-3,~/.config/wallpaper1.jpg"
          "HDMI-A-1,~/.config/wallpaper1.jpg"
        ];
      };
    };

    xdg.configFile = {
      "hypr/hyprland.conf".source = ./hyprland.conf;
      "hypr/start.sh" = {
        source = ./start.sh;
        executable = true;
      };
    };
  };
}
