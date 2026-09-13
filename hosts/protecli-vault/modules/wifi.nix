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
            {password = "PASSWORD_PLACEHOLDER";}
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

  systemd.services."hostapd@${interface}".serviceConfig.ExecStartPre = [
    "bash -c 'sed -i \"s|PASSWORD_PLACEHOLDER|$(cat /run/secrets/ap_password)|\" /etc/hostapd/hostapd.conf'"
  ];

  environment.systemPackages = [pkgs.hostapd];
}
