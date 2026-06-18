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
      '';
    };

    home.packages = [pkgs.oh-my-posh];

    xdg.configFile = {
      "oh-my-posh/config.json".source = ../../../config/oh-my-posh-theme.json;
    };

    programs.git = {
      enable = true;
      userName = "bee";
      userEmail = "your-email@example.com"; # Change this
    };
  };
}
