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
    (builtins.readFile ../config/krisp-patcher.py);
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

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    obsidian
    discord
    brave
    unstable.windsurf
    ntfs3g #for mounting ntfs drives
    alejandra #for formatting in rebuild script
    libnotify #for system notifications
    neofetch
    htop
    gnumake
    krisp-patcher
    hyprshot
    grim #screenshot tool for wayland (hyprshot dependency)
    slurp #region selection tool (hyprshot dependency)
    direnv
    tree
    gh
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];

  boot.binfmt.emulatedSystems = ["aarch64-linux"];

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
