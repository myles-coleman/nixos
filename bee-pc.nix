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
      rebuild = "sh ${config.users.users.${mainUser}.home}/nixos/rebuild.sh";
      windsurf = "windsurf 2>/dev/null"; # hide windsurf warnings
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

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  hardware = {
    graphics.enable = true;
  };

  environment.systemPackages = with pkgs; [
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
    protonup-qt # for steam proton
    obs-studio
    kubectl
    kustomize
    wl-clipboard # wayland clipboard for kubernetes
    jq
    kubernetes-helm
    helmfile
    k9s
    docker
    terraform
    awscli2
    mangohud #for application hardware metrics overlay (isn't working)
    rpi-imager
    # minecraft
    # grim
    # swappy
    # slurp
    r2modman
    htop
    goverlay
    # lutris
    steam-run
    vulkan-tools
    xorg.libX11
    mesa-demos
    mangohud
    krisp-patcher
    dunst
    kitty
    rofi-wayland
    swww
    nerd-fonts.meslo-lg
    meslo-lgs-nf
    font-awesome
    material-icons
    material-design-icons
    networkmanagerapplet
    pamixer
    pavucontrol
    zenity
    blueman
    stown
    nwg-look
    catppuccin-gtk
    kdePackages.dolphin
    wofi
    waybar
    zsh
    gnumake
    mullvad-vpn
    oh-my-posh
  ];

  environment.variables = {
    # MANGOHUD = "1";
    # VK_INSTANCE_LAYERS = "VK_LAYER_MANGOHUD_overlay";
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };

  programs.gamemode.enable = true;

  programs.steam.extraCompatPackages = with pkgs; [
    proton-ge-bin
  ];

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

  # fileSystems."/mnt/harddrive" = {
  #   device = "UUID=060C52F50C52DEED";
  #   fsType = "ntfs-3g";
  #   options = ["uid=1000" "gid=100" "umask=0002"];
  # };

  # fileSystems."/mnt/backup" = {
  #   device = "UUID=01DA7976C02A2420";
  #   fsType = "ntfs-3g";
  #   options = ["uid=1000" "gid=100" "umask=0002"];
  # };

  system.stateVersion = "25.05"; # Did you read the comment?
}
