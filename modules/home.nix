{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";

  home-manager.users.${mainUser} = {
    home.username = mainUser;
    home.homeDirectory = "/home/${mainUser}";
    home.stateVersion = "25.05";

    home.pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 16;
      gtk.enable = true;
      x11.enable = true;
    };

    services.hyprpaper = {
      enable = true;
      settings = {
        ipc = "on";
        splash = false;
        preload = [
          "~/.config/wallpaper1.jpg"
        ];
        wallpaper = [
          "eDP-1,~/.config/wallpaper1.jpg"
          "HDMI-A-1,~/.config/wallpaper1.jpg"
        ];
      };
    };

    programs.kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
      settings = {
        font_family = "CaskaydiaCove Nerd Font Mono";
        bold_font = "auto";
        italic_font = "auto";
        bold_italic_font = "auto";
        font_size = 14;
        background_opacity = "0.9";
      };
    };

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      shellAliases = {
        rebuild = "sh ~/nixos/rebuild.sh";
      };
      oh-my-zsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "colorize"
          "history-substring-search"
        ];
      };
      initContent = ''
        # Initialize Oh My Posh with custom theme
        eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh/config.json)"

        # Fix kitty TERM issue on remote machines that lack xterm-kitty terminfo
        alias ssh="TERM=xterm-256color ssh"
      '';
    };

    home.packages = [pkgs.oh-my-posh pkgs.hyprpaper];

    programs.git = {
      enable = true;
      userName = "Myles Coleman";
      userEmail = "mylescoleman05@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    xdg.configFile = {
      "wallpaper1.jpg".source = ../config/wallpaper1.jpg;

      "rofi/config.rasi".source = ../config/rofi/config.rasi;
      "rofi/catppuccin-mocha.rasi".source = ../config/rofi/catppuccin-mocha.rasi;

      "waybar/config".source = ../config/waybar/config;
      "waybar/style.css".source = ../config/waybar/style.css;

      "MangoHud/MangoHud.conf".source = ../config/mangohud/MangoHud.conf;
      "MangoHud/custom.conf".source = ../config/mangohud/custom.conf;

      "oh-my-posh/config.json".source = ../config/oh-my-posh-theme.json;
    };
  };
}
