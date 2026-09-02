{
  config,
  pkgs,
  lib,
  ...
}: let
  interface = "wlp7s0";
  ssid = "beans-test";
  password = "1password23";
in {
  services.hostapd = {
    enable = true;
    radios."${interface}" = {
      networks."${interface}" = {
        ssid = ssid;
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            {password = password;}
          ];
          # mode = "wpa2-sha256";
          # wpaPassword = password;
        };
        settings = {
          bridge = "br-lan";
          channel = 6;
          hw_mode = "g";
          ieee80211n = 1;
        };
      };
    };
  };

  # Add hostapd to system packages
  environment.systemPackages = [pkgs.hostapd];
}
