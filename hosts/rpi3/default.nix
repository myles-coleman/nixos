{
  config,
  pkgs,
  lib,
  nixos-raspberrypi,
  ...
}: let
  # Kiosk target URL, preserved from the source `rpi3-nixos` configuration.
  kioskUrl = "https://google.com";
  kioskCommand = "${pkgs.cage}/bin/cage -s -- ${pkgs.chromium}/bin/chromium --kiosk --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/tmp/chromium-cache ${kioskUrl}";
in {
  # Chromium kiosk, migrated from `nixos-hardware` + the upstream SD module to
  # the vendor `nixos-raspberrypi` board and SD-image modules.
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-3.base
    nixos-raspberrypi.nixosModules.sd-image
    ../../modules/sops.nix
  ];

  networking = {
    hostName = "rpi3";
    networkmanager = {
      enable = true;
      # Fixed LAN address so deploy-rs can target rpi3 like the k3s nodes.
      # Predictable names are disabled below so the onboard USB ethernet is
      # reliably `eth0`, which this profile matches.
      ensureProfiles.profiles.wired = {
        connection = {
          id = "wired";
          type = "ethernet";
          interface-name = "eth0";
          autoconnect = true;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.0.0.145/24,10.0.0.1";
          dns = "1.1.1.1;";
        };
      };
    };
    # `networking.wireless.enable` is managed by NetworkManager on 26.05;
    # forcing it off here conflicts with the NM module.
    usePredictableInterfaceNames = false;
  };

  users.users.bee = {
    initialPassword = "raspberry";
    isNormalUser = true;
    extraGroups = ["wheel" "video" "input" "networkmanager"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
      # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Password auth is intentionally preserved from the source repo even though
  # the old AGENTS.md claimed key-only access (see task 3.6).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };

  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = kioskCommand;
        user = "bee";
      };
      default_session = {
        command = kioskCommand;
        user = "bee";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    networkmanager
    chromium
    cage
  ];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  boot.kernelModules = ["i2c-dev"];

  # ── Declarative firmware config.txt (task 3.2) ──────────────────────
  # Replaces the imperative firmware-config.txt oneshot. The vendor module
  # renders config.txt at image-build time and already defaults:
  #   arm_64bit, enable_uart, avoid_warnings, disable_overscan,
  #   display_auto_detect, and the `vc4-kms-v3d` overlay.
  # The two remaining source options that are not vendor defaults are kept.
  # The old `kernel=u-boot-rpi3.bin` lines are intentionally dropped: the
  # vendor `raspberry-pi-3.base` sets `boot.loader.raspberry-pi.bootloader`
  # and owns kernel selection, so setting `kernel=` by hand would conflict.
  hardware.raspberry-pi.config = {
    all.options.gpu_mem = {
      enable = true;
      value = 128;
    };
    pi3.options.core_freq = {
      enable = true;
      value = 250;
    };
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 2048; # MB
    }
  ];

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Keep the SD image uncompressed; preserved from the source config.
  sdImage.compressImage = false;

  system.stateVersion = "25.05";
}
