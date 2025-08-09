{
  config,
  pkgs,
  lib,
  ...
}: {
  users.users.bee = {
    isNormalUser = true;
    description = "bee";
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
        user = "bee";
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
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  hardware = {
    graphics.enable = true;
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
    # xorg.libX11
    zenity #power button stuff
    blueman #bluetooth manager
    lutris #game launcher
    stown #sets symlinks for dotfiles to ~/.config
    toybox #gives unix utilities like `killall`
    pcmanfm #file manager
    nwg-look #themeing gtk apps
    catppuccin-gtk #catppuccin theme
    prismlauncher #minecraft launcher
    r2modman
    htop
    kdePackages.dolphin
    wofi
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

  # fileSystems."/mnt/harddrive" = {
  #   device = "UUID=060C52F50C52DEED";
  #   fsType = "ntfs-3g";
  #   options = ["uid=1000" "gid=100" "umask=0002"];
  # };

  #  fileSystems."/mnt/backup" = {
  #    device = "UUID=01DA7976C02A2420";
  #    fsType = "ntfs-3g";
  #    options = ["uid=1000" "gid=100" "umask=0002"];
  #  };

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
