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
          mode = "wpa2-sha256";
          wpaPassword = password;
        };
        settings = {
          channel = 6;
          hw_mode = "g";
          ieee80211n = 1;
        };
      };
    };
  };

  # Ensure the wireless interface is bridged to br-lan
  systemd.network.networks."30-wifi" = {
    matchConfig.Name = interface;
    networkConfig = {
      Bridge = "br-lan";
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Add hostapd to system packages
  environment.systemPackages = [pkgs.hostapd];
}
