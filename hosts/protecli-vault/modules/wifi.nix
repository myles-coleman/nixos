{
  config,
  pkgs,
  lib,
  ...
}: let
  interface = "wlp7s0";
  ssid = "beans-test";
in {
  # The AP password lives in sops; sops-nix materializes it at
  # /run/secrets/ap_password before multi-user.target.
  sops.secrets.ap_password = {};

  services.hostapd = {
    enable = true;
    radios."${interface}" = {
      band = "2g";
      countryCode = "US";
      # iwlwifi on this box cannot do ACS ("Unable to collect survey data"),
      # and the module defaults channel to 0 (= ACS). Pin the channel.
      channel = 6;
      # Add wlp7s0 to the LAN bridge so wireless clients share the
      # 192.168.1.0/24 network and Pi-hole DHCP. hostapd enslaves the
      # interface itself; networkd must not manage wlp7s0 (it doesn't).
      settings.bridge = "br-lan";
      networks."${interface}" = {
        ssid = ssid;
        authentication = {
          mode = "wpa3-sae";
          # Read the password from the sops secret at service start instead
          # of embedding it (which would land plaintext in the nix store).
          saePasswords = [
            {passwordFile = "/run/secrets/ap_password";}
          ];
        };
      };
    };
  };

  # hostapd needs br-lan (created by systemd-networkd) to exist before it
  # can enslave wlp7s0.
  systemd.services.hostapd = {
    after = ["systemd-networkd.service"];
    wants = ["systemd-networkd.service"];
  };

  environment.systemPackages = [pkgs.iw];
}
