{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
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
      rebuild = "sh ${config.users.users.${mainUser}.home}/nixos/rebuild.sh";
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

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "Hyprland";
        user = "bee";
      };
    };
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Environment variables
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  hardware = {
    graphics.enable = true;
  };

  environment.systemPackages = with pkgs; [
    dunst
    kitty
    rofi-wayland
    libnotify
    swww
    nerd-fonts.meslo-lg ## Fonts and Icons
    meslo-lgs-nf
    font-awesome
    material-icons
    material-design-icons ## ^^^^^^^^^^^^^
    vim
    wget
    git
    obsidian
    discord
    brave
    windsurf
    ntfs3g #for mounting ntfs drives
    alejandra #for formatting in rebuild script
    libnotify #for system notifications
    neofetch
    networkmanagerapplet
    pamixer
    pavucontrol
    mangohud
    mesa-demos
    vulkan-tools
    # xorg.libX11
    zenity #power button stuff
    blueman #bluetooth manager
    stown #sets symlinks for dotfiles to ~/.config
    toybox #gives unix utilities like `killall`
    pcmanfm #file manager
    nwg-look #themeing gtk apps
    catppuccin-gtk #catppuccin theme
    htop
    kdePackages.dolphin
    wofi
    waybar
    zsh
    zsh-autosuggestions
    brightnessctl #brightness control
    calibre
    ethtool
    docker
    gnumake
    mullvad-vpn
    oh-my-posh
    tmux
  ];

  environment.variables = {
    # MANGOHUD = "1";
  };

  virtualisation.docker.enable = true;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both"; # Allow this machine to use AND be an exit node
    openFirewall = true;
  };

  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  fileSystems."/home/bee/media" = {
    device = "10.0.0.150:/mnt/md0/data/media";
    fsType = "nfs4";
    options = [
      "rw"
      "soft"
      "timeo=30"
      "retrans=3"
      "_netdev"
      "rsize=1048576"
      "wsize=1048576"
      "vers=4.2"
      "proto=tcp"
    ];
  };

  services.rpcbind.enable = true;

  # Font configuration
  fonts = {
    enableDefaultPackages = true;
    fontDir.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      nerd-fonts.meslo-lg
      meslo-lgs-nf
      font-awesome
      material-icons
      material-design-icons
    ];
    fontconfig = {
      defaultFonts = {
        monospace = ["MesloLGS Nerd Font Mono"];
        sansSerif = ["Noto Sans"];
        serif = ["Noto Serif"];
      };
    };
  };

  # Manual Oh My Posh configuration
  environment.etc."oh-my-posh-config.json" = {
    text = builtins.readFile "${config.users.users.${mainUser}.home}/dotfiles/oh-my-posh/.config/oh-my-posh/custom-theme.omp.json";
    mode = "0644";
  };

  programs.zsh.interactiveShellInit = ''
    # Initialize Oh My Posh with custom theme
    eval "$(oh-my-posh init zsh --config /etc/oh-my-posh-config.json)"
  '';

  xdg.portal.enable = true;
  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];

  # Enable sound with PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
  services.blueman.enable = true;

  system.stateVersion = "25.05";
}
