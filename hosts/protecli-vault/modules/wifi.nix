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

  # ath10k needs the regulatory domain in place before the phy registers.
  # A phy created under the world domain (00) marks the whole 5GHz band
  # NO-IR, and hostapd's own country_code=US cannot clear it afterwards:
  #
  #   Frequency 5745 (primary) not allowed for AP mode, flags: 0x853 NO-IR
  #   Could not select hw_mode and channel. (-3)
  #
  # That is exactly what happens after a bare `modprobe -r ath10k_pci`, so
  # set the cfg80211 hint rather than relying on hostapd to set it later.
  boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=US";

  # 6.18.64 regression: the modprobe hint alone no longer prevents the phy
  # from being registered under the world domain, which marks the whole 5 GHz
  # band NO-IR and makes hostapd fail with "Hardware does not support
  # configured channel". Pass the hint on the kernel command line and reload
  # ath10k after setting the reg domain, so the phy is created under US before
  # hostapd runs.
  boot.kernelParams = ["cfg80211.ieee80211_regdom=US"];

  services.hostapd = {
    enable = true;
    radios."${interface}" = {
      # Qualcomm Atheros QCA6174A-5 (ath10k), 2x2 802.11ac.
      #
      # This radio runs 5GHz only. The card serves one band at a time, so
      # 2.4GHz-only clients get no WiFi from this box — notably the rpi3
      # kiosk (Pi 3B, 2.4GHz-only radio), which already has a wired eth0
      # profile in hosts/rpi3/default.nix. Wire it instead.
      band = "5g";
      countryCode = "US";
      # UNII-3, explicitly non-DFS. 80MHz spans channels 149-161, whose
      # centre segment index is 155. Avoid UNII-2/2C: DFS means radar
      # detection can drop the AP.
      channel = 149;
      # HT40 is a prerequisite for an 80MHz VHT channel. The module's default
      # is a bare "HT40" token that hostapd ignores, so name the direction:
      # primary 149, secondary above.
      wifi4.capabilities = ["HT40+" "SHORT-GI-20" "SHORT-GI-40"];
      wifi5 = {
        enable = true;
        operatingChannelWidth = "80";
      };
      # 802.11ac card — advertising HE would make hostapd reject the config.
      wifi6.enable = false;
      settings = {
        # hostapd adds wlp7s0 to the WiFi bridge, which carries 10.50.0.0/24
        # and its own networkd DHCP scope. networkd never matches wlp7s0.
        bridge = "br-wifi";
        # The NixOS module emits vht_oper_chwidth but not the centre segment
        # index, and hostapd needs both for 80MHz.
        vht_oper_centr_freq_seg0_idx = 155;
      };
      networks."${interface}" = {
        ssid = ssid;
        # Clients cannot talk to each other at L2; everything goes through the
        # Vault, where the segment firewall decides. This must be the typed
        # `apIsolate` option: a freeform `settings.ap_isolate` is emitted
        # before the option's default and loses to it.
        apIsolate = true;
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

  # hostapd needs br-wifi (created by systemd-networkd) to exist before it
  # can enslave wlp7s0.
  systemd.services.hostapd = {
    after = ["systemd-networkd.service" "ath10k-regdomain.service"];
    wants = ["systemd-networkd.service" "ath10k-regdomain.service"];
  };

  # Recreate the ath10k phy under the US regulatory domain. Setting the reg
  # domain after the phy exists is too late: the driver keeps the world-domain
  # NO-IR flags for 5 GHz and hostapd cannot clear them.
  systemd.services.ath10k-regdomain = {
    description = "Set the US regulatory domain before hostapd starts";
    before = ["hostapd.service"];
    after = ["systemd-modules-load.service" "systemd-networkd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iw}/bin/iw reg set US || true
      ${pkgs.kmod}/bin/modprobe -r ath10k_pci || true
      ${pkgs.kmod}/bin/modprobe ath10k_pci || true
      n=0
      while [ "$n" -lt 20 ] && [ ! -e /sys/class/net/wlp7s0 ]; do
        n=$((n + 1))
        ${pkgs.coreutils}/bin/sleep 0.5
      done
    '';
  };

  environment.systemPackages = [pkgs.iw];
}
