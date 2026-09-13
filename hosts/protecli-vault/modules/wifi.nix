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
            {password = "dummy-password-to-satisfy-nix-validation";}
          ];
        };
      };
    };
  };

  sops.templates."hostapd.conf" = {
    path = "/run/hostapd/hostapd.conf.template";
    content = ''
      interface=${interface}
      ssid=${ssid}
      driver=nl80211
      hw_mode=g
      ieee80211n=1
      wpa=3
      wpa_key_mgmt=SAE
      sae_password=PASSWORD_PLACEHOLDER
      bridge=br-lan
      channel=6
    '';
  };

  systemd.services."hostapd@${interface}.service" = {
    after = ["sops-nix.service"];
    serviceConfig = {
      ExecStartPre = ''
        mkdir -p /run/hostapd
        sed "s|PASSWORD_PLACEHOLDER|$(cat /run/secrets/ap_password)|g" /run/hostapd/hostapd.conf.template > /run/hostapd/hostapd.conf
      '';
      ExecStart = ''
        ${pkgs.hostapd}/bin/hostapd /run/hostapd/hostapd.conf
      '';
    };
  };

  environment.systemPackages = [pkgs.hostapd];
}
