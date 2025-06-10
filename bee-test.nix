{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  # boot.kernelPackages = pkgs.linuxPackages_6_1;

  boot.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
  boot.kernelParams = ["nvidia-drm.modeset=1"];

  users.users.mylesc = {
    isNormalUser = true;
    description = "Myles Coleman";
    extraGroups = ["networkmanager" "wheel" "input"];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
  };

  # Use greetd for login and auto-start Hyprland
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "Hyprland";
        user = "mylesc";
      };
    };
  };

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Environment variables
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Hardware configuration
  services.xserver.videoDrivers = ["nvidia"];

  hardware = {
    graphics.enable = true;
    nvidia.modesetting.enable = true;
    nvidia.open = false;
    nvidia.powerManagement.enable = false;
    nvidia.powerManagement.finegrained = false;
    nvidia.nvidiaSettings = false;
    # nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

    nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "570.153.02";
      sha256_64bit = "sha256-FIiG5PaVdvqPpnFA5uXdblH5Cy7HSmXxp6czTfpd4bY=";
      sha256_aarch64 = "sha256-FIiG5PaVdvqPpnFA5uXdblH5Cy7HSmXxp6czTfpd4bY=";
      openSha256 = "sha256-FIiG5PaVdvqPpnFA5uXdblH5Cy7HSmXxp6czTfpd4bY=";
      settingsSha256 = "sha256-FIiG5PaVdvqPpnFA5uXdblH5Cy7HSmXxp6czTfpd4bY=";
      persistencedSha256 = "sha256-FIiG5PaVdvqPpnFA5uXdblH5Cy7HSmXxp6czTfpd4bY=";
    };

    # nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    #   version = "560.35.03";
    #   sha256_64bit = "sha256-8pMskvrdQ8WyNBvkU/xPc/CtcYXCa7ekP73oGuKfH+M=";
    #   sha256_aarch64 = "sha256-8pMskvrdQ8WyNBvkU/xPc/CtcYXCa7ekP73oGuKfH+M=";
    #   openSha256 = "sha256-8pMskvrdQ8WyNBvkU/xPc/CtcYXCa7ekP73oGuKfH+M=";
    #   settingsSha256 = "sha256-8pMskvrdQ8WyNBvkU/xPc/CtcYXCa7ekP73oGuKfH+M=";
    #   persistencedSha256 = "sha256-8pMskvrdQ8WyNBvkU/xPc/CtcYXCa7ekP73oGuKfH+M=";
    # };

    # nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    #   version = "550.40.07";
    #   sha256_64bit = "sha256-KYk2xye37v7ZW7h+uNJM/u8fNf7KyGTZjiaU03dJpK0=";
    #   sha256_aarch64 = "sha256-AV7KgRXYaQGBFl7zuRcfnTGr8rS5n13nGUIe3mJTXb4=";
    #   openSha256 = "sha256-mRUTEWVsbjq+psVe+kAT6MjyZuLkG2yRDxCMvDJRL1I=";
    #   settingsSha256 = "sha256-c30AQa4g4a1EHmaEu1yc05oqY01y+IusbBuq+P6rMCs=";
    #   persistencedSha256 = "sha256-11tLSY8uUIl4X/roNnxf5yS2PQvHvoNjnd2CB67e870=";
    # };

    # nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    #   version = "555.58.02";
    #   sha256_64bit = "sha256-xctt4TPRlOJ6r5S54h5W6PT6/3Zy2R4ASNFPu8TSHKM=";
    #   sha256_aarch64 = "sha256-8hyRiGB+m2hL3c9MDA/Pon+Xl6E788MZ50WrrAGUVuY=";
    #   openSha256 = "sha256-8hyRiGB+m2hL3c9MDA/Pon+Xl6E788MZ50WrrAGUVuY=";
    #   settingsSha256 = "sha256-ZpuVZybW6CFN/gz9rx+UJvQ715FZnAOYfHn5jt5Z2C8=";
    #   persistencedSha256 = "sha256-xctt4TPRlOJ6r5S54h5W6PT6/3Zy2R4ASNFPu8TSHKM=";
    # };
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  environment.systemPackages = with pkgs; [
    dunst
    kitty
    starship #kitty configuration
    rofi-wayland
    libnotify
    swww
    waybar
    (waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ ["-Dexperimental=true"];
    }))
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
    xorg.libX11
    zenity #power button stuff
    blueman #bluetooth manager
    lutris #game launcher
    stown #sets symlinks for dotfiles to ~/.config
    toybox #gives unix utilities like `killall`
    pcmanfm #file manager
    nwg-look #themeing gtk apps
    catppuccin-gtk #catppuccin theme
    prismlauncher #minecraft launcher
  ];

  environment.variables = {
    # MANGOHUD = "1";
  };

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

  programs.starship = {
    enable = true;
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

  fileSystems."/mnt/harddrive" = {
    device = "UUID=060C52F50C52DEED";
    fsType = "ntfs-3g";
    options = ["uid=1000" "gid=100" "umask=0002"];
  };

  fileSystems."/mnt/backup" = {
    device = "UUID=01DA7976C02A2420";
    fsType = "ntfs-3g";
    options = ["uid=1000" "gid=100" "umask=0002"];
  };

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

  # Start the bluetooth service
  services.blueman.enable = true;

  # Example rofi keybind (assuming using Hyprland's config in ~/.config/hypr/hyprland.conf, not in NixOS config)
  # This would go in hyprland.conf, not in NixOS configuration.nix:
  #
  # bind = $mainMod, S, exec, rofi -show drun -show-icons
  system.stateVersion = "25.05";
}
