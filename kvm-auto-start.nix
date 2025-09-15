# KVM Auto-Detection Service for NixOS
# Import this file in your configuration.nix:
#   imports = [ ./kvm-auto-start.nix ];
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Auto-detection service
  # Monitors for HDMI capture device and automatically starts KVM mode
  systemd.user.services.kvm-auto-detect = {
    description = "KVM Auto-Detection";
    # Comment out wantedBy to disable auto-start
    # wantedBy = [ "graphical-session.target" ];
    after = ["graphical-session.target"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash /home/bee/nixos/kvm-auto-detect.sh start";
      ExecStop = "${pkgs.bash}/bin/bash /home/bee/nixos/kvm-auto-detect.sh stop";
      Restart = "on-failure";
      RestartSec = 5;
    };

    environment = {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
      PATH = lib.mkForce (lib.makeBinPath (with pkgs; [
        bash
        v4l-utils
        procps
        libnotify
        coreutils
        mpv
        ffmpeg
      ]));
    };
  };

  # Ensure user has necessary groups for device access
  users.users.bee = {
    extraGroups = ["video" "input" "dialout"];
  };

  # Install required packages for KVM
  environment.systemPackages = with pkgs; [
    v4l-utils
    libnotify
  ];

  # Hyprland keybindings for KVM toggle
  # Add these to your Hyprland config or uncomment to auto-add
  # programs.hyprland.extraConfig = ''
  #   # Toggle KVM with Super+K
  #   bind = SUPER, K, exec, /home/bee/nixos/kvm-switch.sh
  #
  #   # Dedicate workspace 10 to KVM
  #   workspace = 10, monitor:eDP-1, default:false
  # '';
}
