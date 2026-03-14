{
  config,
  pkgs,
  lib,
  ...
}: {
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

  environment.variables = {
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    AWS_PROFILE = "homelab";
  };

  hardware = {
    graphics.enable = true;
  };

  environment.systemPackages = with pkgs; [
    dunst
    kitty
    rofi-wayland
    swww
    networkmanagerapplet
    pamixer
    pavucontrol
    zenity
    blueman
    nwg-look
    catppuccin-gtk
    kdePackages.dolphin
    wofi
    waybar
  ];

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
}
