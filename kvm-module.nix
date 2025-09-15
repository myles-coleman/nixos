# KVM module configuration for GPD Pocket 4
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Install necessary packages for video capture and display
  environment.systemPackages = with pkgs; [
    v4l-utils # Video4Linux utilities
    ffmpeg # For video processing
    mpv # For displaying video
    guvcview # USB video viewer
    usbutils # For lsusb and other USB tools
    wf-recorder # Wayland screen recorder
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    # Packages for touchscreen forwarding
    python3
    python3Packages.evdev
    python3Packages.pyudev
    socat
    libevdev
  ];

  # Load the necessary kernel modules for video capture
  boot.kernelModules = [
    "uvcvideo" # USB Video Class driver
    "v4l2loopback" # Video4Linux loopback device
  ];

  # Create a persistent v4l2loopback device
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  # Configure the v4l2loopback module
  boot.extraModprobeConfig = ''
    options v4l2loopback exclusive_caps=1 card_label="KVM Input"
  '';

  # Add udev rules for the KVM module
  services.udev.extraRules = ''
    # GPD Pocket 4 KVM module rules
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", MODE="0666"
    SUBSYSTEM=="video4linux", KERNEL=="video*", ATTRS{name}=="HDMI Capture", SYMLINK+="kvm-input"
    # Also create a symlink for the specific device we know works
    SUBSYSTEM=="video4linux", KERNEL=="video3", SYMLINK+="kvm-input-video3"
  '';

  # Add a service to automatically start the KVM input viewer
  systemd.user.services.kvm-viewer = {
    description = "KVM Input Viewer";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    serviceConfig = {
      ExecStart = "${pkgs.mpv}/bin/mpv --profile=low-latency --untimed --no-fullscreen --geometry=800x600 --title='KVM Input' --force-window=yes /dev/kvm-input";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      # Environment variables for the service
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
    };
  };

  # Add a script to toggle the KVM input
  environment.etc."kvm-toggle.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh

      if pgrep -f "mpv.*kvm-input" > /dev/null; then
        pkill -f "mpv.*kvm-input"
        echo "KVM input viewer stopped"
      else
        mpv --profile=low-latency --untimed --no-fullscreen --geometry=800x600 --title="KVM Input" --force-window=yes /dev/kvm-input &
        echo "KVM input viewer started in windowed mode"
      fi
    '';
  };

  # Add a keybinding to toggle the KVM input in Hyprland
  # This will be added to your user's Hyprland config
}
