{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable the X11 windowing system and Plasma 6
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable Wayland support
  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };

  # Enable graphics
  hardware = {
    graphics.enable = true;
  };

  # KDE/Plasma system packages
  environment.systemPackages = with pkgs; [
    kdePackages.plasma-browser-integration
    kdePackages.kdeconnect-kde
    kdePackages.kate
    kdePackages.dolphin
    kdePackages.konsole
    kdePackages.gwenview
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.okular
    kdePackages.filelight
    kdePackages.kcalc
    kdePackages.partitionmanager
  ];

  # Enable KDE Connect
  programs.kdeconnect.enable = true;

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

  # Font configuration
  fonts = {
    enableDefaultPackages = true;
    fontDir.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      nerd-fonts.meslo-lg
      font-awesome
      liberation_ttf
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
