{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.home-zsh.enable = lib.mkEnableOption "shared home-manager zsh + oh-my-posh setup";

  config = lib.mkIf config.my.roles.home-zsh.enable {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "backup";

    home-manager.users.bee = {
      home.username = "bee";
      home.homeDirectory = "/home/bee";
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
        "oh-my-posh/config.json".source = ../../config/oh-my-posh-theme.json;
      };
    };
  };
}
