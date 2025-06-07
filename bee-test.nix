{ config, pkgs, ... }:

{

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mylesc = {
    isNormalUser = true;
    description = "Myles Coleman";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
  };

  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.defaultSession = "hyprland";

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Environment variables
  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1";
  };

  # Hardware configuration
  hardware = {
    graphics.enable = true;
    nvidia.modesetting.enable = true;
  };

  environment.systemPackages = with pkgs; [
    dunst
    kitty
    rofi-wayland
    libnotify
    swww
    (waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
    }))
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
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

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

  # Example rofi keybind (assuming using Hyprland's config in ~/.config/hypr/hyprland.conf, not in NixOS config)
  # This would go in hyprland.conf, not in NixOS configuration.nix:
  #
  # bind = $mainMod, S, exec, rofi -show drun -show-icons
  system.stateVersion = "25.05";
}
