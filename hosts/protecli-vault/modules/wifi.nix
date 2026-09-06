{
  config,
  pkgs,
  lib,
  ...
}: let
  interface = "wlp7s0";
  ssid = "beans-test";
in {
  sops.secrets.ap_password = {};

  services.hostapd = {
    enable = true;
    radios."${interface}" = {
      networks."${interface}" = {
        ssid = ssid;
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            {password = config.sops.secrets.ap_password.path;}
          ];
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

  environment.systemPackages = [pkgs.hostapd];
}
