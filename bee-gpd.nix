{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
  unstable = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  }) {config = config.nixpkgs.config;};
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
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.open = true;

  # Enable IOMMU
  boot.kernelParams = ["amd_iommu=on" "iommu=pt"];

  # Kernel modules for game controllers and NVIDIA CUDA
  boot.kernelModules = ["hid_nintendo" "joydev" "nvidia-uvm"];

  # Enable joystick support
  hardware.uinput.enable = true;

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
    unstable.windsurf
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
    python313Packages.cmake
    nvtopPackages.nvidia
    mpv
    opencode
    ollama
  ];

  environment.variables = {
    # MANGOHUD = "1";
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

  services.hardware.bolt.enable = true;

  services.udev.packages = with pkgs; [
    bolt
  ];

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

  # tmux config
  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      tmuxPlugins.sensible
    ];
    # extraConfig = ''
    # ...
    # '';
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];

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
        Experimental = true;
        KernelExperimental = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
    input = {
      General = {
        ClassicBondedOnly = false;
      };
    };
  };
  services.blueman.enable = true;

  # Ollama service with GPU support
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    environmentVariables = {
      OLLAMA_HOST = "127.0.0.1:11434";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    models = "/var/lib/ollama/models";
    loadModels = ["qwen2.5-coder:7b"];
  };

  # Allow Ollama to access GPU devices
  systemd.services.ollama = {
    serviceConfig = {
      DeviceAllow = [
        "/dev/nvidia0 rwm"
        "/dev/nvidiactl rwm"
        "/dev/nvidia-modeset rwm"
        "/dev/nvidia-uvm rwm"
        "/dev/nvidia-uvm-tools rwm"
      ];
      PrivateDevices = false;
    };
  };

  # Ensure opencode npm dependencies are installed
  systemd.user.services.opencode-setup = {
    description = "Install opencode npm dependencies";
    wantedBy = ["default.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p $HOME/.cache/opencode && echo '\"'\"'{\"dependencies\":{\"@ai-sdk/openai-compatible\":\"1.0.31\"}}'\"'\"' > $HOME/.cache/opencode/package.json && cd $HOME/.cache/opencode && ${pkgs.nodejs}/bin/npm install'";
    };
  };

  system.stateVersion = "25.05";
}
