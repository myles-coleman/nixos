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
        # Initialize Oh My Posh with custom theme (only on local sessions)
        if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
          eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh/config.json)"
        fi

        # Fix kitty TERM issue on remote machines that lack xterm-kitty terminfo
        alias ssh="TERM=xterm-256color ssh"
      '';
    };

    programs.oh-my-posh = {
      enable = true;
      enableZshIntegration = false;
      settings = builtins.fromJSON (builtins.readFile ../config/oh-my-posh-theme.json);
    };

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
      "rofi/config.rasi".source = ../config/rofi/config.rasi;
      "rofi/catppuccin-mocha.rasi".source = ../config/rofi/catppuccin-mocha.rasi;

      "waybar/config".source = ../config/waybar/config;
      "waybar/style.css".source = ../config/waybar/style.css;

      "MangoHud/MangoHud.conf".source = ../config/mangohud/MangoHud.conf;
      "MangoHud/custom.conf".source = ../config/mangohud/custom.conf;
    };
  };
}
