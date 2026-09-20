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
      # NOTE: the Intel AX200 cannot run a 5GHz AP on Linux. Its firmware
      # enforces "self-managed" LAR (Location-Aware Regulatory) and every
      # 5GHz channel reports NO-IR, so hostapd refuses to start. lar_disable
      # no longer exists in this kernel. 2.4GHz is all that works.
      band = "2g";
      countryCode = "US";
      # iwlwifi cannot do ACS ("Unable to collect survey data"), and the
      # module defaults channel to 0 (= ACS). Pin the channel.
      channel = 6;
      # 2.4GHz tops out at 40MHz. The module's default ht_capab uses bare
      # "HT40", which hostapd ignores, so request HT40+ explicitly and
      # enable HE (WiFi 6) for 2x2 HE40 (688 Mbps PHY). Channel 6 allows
      # HT40+ in the US (secondary above, channels 4-9).
      # hostapd's OBSS scan sees neighbours on ch 1/6/11 and falls back to
      # 20MHz, so disable it to actually hold 40MHz. This overlaps the
      # adjacent 20MHz networks (a conscious interference tradeoff).
      noScan = true;
      wifi4.capabilities = ["HT40+" "SHORT-GI-20" "SHORT-GI-40"];
      wifi5.enable = false; # VHT is 5GHz-only
      wifi6 = {
        enable = true;
        operatingChannelWidth = "20or40";
      };
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
