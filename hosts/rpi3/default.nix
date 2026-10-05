{
  config,
  inputs,
  ...
}: {
  # Chromium kiosk, migrated from `nixos-hardware` + the upstream SD module to
  # the vendor `nixos-raspberrypi` board and SD-image modules. Host aspect
  # (spec 16): shares no k3s aspects; vendor modules + sops stay plain imports.
  flake.modules.nixos.rpi3 = {pkgs, ...}: {
    imports = [
      inputs.nixos-raspberrypi.nixosModules.raspberry-pi-3.base
      inputs.nixos-raspberrypi.nixosModules.sd-image
      ./modules/kiosk.nix
      ./modules/firmware.nix
      ./modules/users.nix
      ../../modules/sops.nix
      inputs.sops-nix.nixosModules.sops
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

    environment.systemPackages = with pkgs; [
      vim
      htop
      networkmanager
      chromium
      cage
    ];

    time.timeZone = "America/Los_Angeles";
    i18n.defaultLocale = "en_US.UTF-8";

    swapDevices = [
      {
        device = "/swapfile";
        size = 2048; # MB
      }
    ];

    system.stateVersion = "25.05";
  };
}
