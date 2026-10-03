{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  my.roles.home-zsh.enable = true;

  home-manager.users.${mainUser} = {
    home.pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 16;
      gtk.enable = true;
      x11.enable = true;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
      settings = {
        font_family = "CaskaydiaCove Nerd Font Mono";
        bold_font = "auto";
        italic_font = "auto";
        bold_italic_font = "auto";
        font_size = 16;
        background_opacity = "0.9";
        window_padding_width = 10;
      };
    };

    # bee-pc/bee-gpd append their extra init content (direnv hook + ssh alias)
    # after the shared oh-my-posh block provided by my.roles.home-zsh.
    programs.zsh.initContent = lib.mkOrder 1010 ''
      # Re-initialize direnv hook after oh-my-posh to prevent precmd clobbering
      eval "$(direnv hook zsh)"

      # Fix kitty TERM issue on remote machines that lack xterm-kitty terminfo
      alias ssh="TERM=xterm-256color ssh"
    '';

    home.packages = [pkgs.hyprpaper];

    programs.git = {
      enable = true;
      settings = {
        user = {
          name = "Myles Coleman";
          email = "mylescoleman05@gmail.com";
        };
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    home.file = {
      ".claude/commands/SDD-1-generate-spec.md".source = ../config/claude-commands/SDD-1-generate-spec.md;
      ".claude/commands/SDD-2-generate-task-list-from-spec.md".source = ../config/claude-commands/SDD-2-generate-task-list-from-spec.md;
      ".claude/commands/SDD-3-manage-tasks.md".source = ../config/claude-commands/SDD-3-manage-tasks.md;
      ".claude/commands/SDD-4-validate-spec-implementation.md".source = ../config/claude-commands/SDD-4-validate-spec-implementation.md;

      # OpenCode skills - each skill needs its own directory with SKILL.md inside
      ".config/opencode/skills/sdd-1-generate-spec/SKILL.md".source = ../config/claude-commands/SDD-1-generate-spec.md;
      ".config/opencode/skills/sdd-2-generate-task-list-from-spec/SKILL.md".source = ../config/claude-commands/SDD-2-generate-task-list-from-spec.md;
      ".config/opencode/skills/sdd-3-manage-tasks/SKILL.md".source = ../config/claude-commands/SDD-3-manage-tasks.md;
      ".config/opencode/skills/sdd-4-validate-spec-implementation/SKILL.md".source = ../config/claude-commands/SDD-4-validate-spec-implementation.md;
      #      ".config/opencode/tools/websearch.ts".source = ../config/opencode/tools/websearch.ts;
    };

    xdg.configFile = {
      "wallpaper1.jpg".source = ../config/wallpaper1.jpg;

      "rofi/config.rasi".source = ../config/rofi/config.rasi;
      "rofi/catppuccin-mocha.rasi".source = ../config/rofi/catppuccin-mocha.rasi;

      "waybar/config".source = ../config/waybar/config;
      "waybar/style.css".source = ../config/waybar/style.css;
      "waybar/wvkbd-toggle.sh" = {
        source = ../config/waybar/wvkbd-toggle.sh;
        executable = true;
      };

      "MangoHud/MangoHud.conf".source = ../config/mangohud/MangoHud.conf;
      "MangoHud/custom.conf".source = ../config/mangohud/custom.conf;
    };
  };
}
