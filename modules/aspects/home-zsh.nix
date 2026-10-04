{config, ...}: {
  # NixOS half: owns the `home-manager.*` globals and the `bee` user's Home
  # Manager entry, and wires the Home Manager half in. `home-manager.*` are
  # NixOS options, so they must not appear in the homeManager half below.
  flake.modules.nixos.home-zsh = {...}: {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "backup";

    home-manager.users.bee = {
      imports = [
        config.flake.modules.homeManager.home-zsh
      ];

      home.username = "bee";
      home.homeDirectory = "/home/bee";
      home.stateVersion = "25.05";
    };
  };

  # Home Manager half: the shared zsh + oh-my-posh setup.
  flake.modules.homeManager.home-zsh = {pkgs, ...}: {
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
}
