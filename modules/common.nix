{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
  krisp-patcher =
    pkgs.writers.writePython3Bin "krisp-patcher"
    {
      libraries = with pkgs.python3Packages; [
        capstone
        pyelftools
      ];
      flakeIgnore = [
        "E501" # line too long (82 > 79 characters)
        "F403" # 'from module import *' used; unable to detect undefined names
        "F405" # name may be undefined, or defined from star imports: module
      ];
    }
    (
      builtins.readFile (
        pkgs.fetchurl {
          url = "https://pastebin.com/raw/8tQDsMVd";
          sha256 = "sha256-IdXv0MfRG1/1pAAwHLS2+1NESFEz2uXrbSdvU9OvdJ8=";
        }
      )
    );
in {
  users.users.${mainUser} = {
    isNormalUser = true;
    description = mainUser;
    extraGroups = ["networkmanager" "wheel" "input" "docker"];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    shellAliases = {
      rebuild = "sh ~/nixos/rebuild.sh";
    };
    ohMyZsh = {
      enable = true;
      plugins = [
        "colored-man-pages"
        "colorize"
        "history-substring-search"
      ];
    };
  };

  # Manual Oh My Posh configuration
  environment.etc."oh-my-posh-config.json" = {
    text = builtins.readFile "${config.users.users.${mainUser}.home}/dotfiles/oh-my-posh/.config/oh-my-posh/custom-theme.omp.json";
    mode = "0644";
  };

  programs.zsh.interactiveShellInit = ''
    # Initialize Oh My Posh with custom theme (only on local sessions)
    if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
      eval "$(oh-my-posh init zsh --config /etc/oh-my-posh-config.json)"
    fi
  '';

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    obsidian
    discord
    brave
    unstable.windsurf
    ntfs3g #for mounting ntfs drives
    alejandra #for formatting in rebuild script
    libnotify #for system notifications
    neofetch
    htop
    stown
    gnumake
    oh-my-posh
    zsh
    krisp-patcher
    hyprshot
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "bee"];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  virtualisation.docker.enable = true;
}
