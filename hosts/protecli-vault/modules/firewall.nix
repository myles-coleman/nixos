{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  mgmt = "enp6s0";
  wifi = "wlp7s0";
in {
  # ── Enable nftables, disable default NixOS firewall ────────────────
  networking.nftables.enable = true;
  networking.nftables.checkRuleset = false;
  networking.firewall.enable = lib.mkForce false;

  # ── Complete nftables ruleset ──────────────────────────────────────
  networking.nftables.ruleset = ''
    table inet filter {
      chain input {
        type filter hook input priority 0; policy drop;

        # drop invalid packets
        ct state invalid drop

        # SAFETY: management port always allowed (lockout protection)
        iifname "${mgmt}" accept comment "SAFETY: management port always allowed"

        # Loopback
        iifname "lo" accept comment "allow loopback"

        # LAN and WiFi traffic to router
        iifname "br-lan" accept comment "allow LAN traffic to router"
        iifname "${wifi}" accept comment "allow WiFi traffic to router"

        # Allow DHCP and DNS from WiFi interface
        iifname "${wifi}" udp dport { 67, 68, 53 } accept comment "allow DHCP/DNS from WiFi"

        # Tailscale
        iifname "tailscale0" accept comment "allow Tailscale traffic"

        # WAN: only established/related connections
        iifname "${wan}" ct state { established, related } accept comment "allow established WAN traffic"

        # WAN: select ICMP types
        iifname "${wan}" icmp type { echo-request, destination-unreachable, time-exceeded } counter accept comment "allow select ICMP from WAN"

        # WAN: log and drop everything else (rate-limited)
        iifname "${wan}" counter log prefix "dropped: " limit rate 5/minute drop comment "log and drop all other WAN input"
      }

      chain forward {
        type filter hook forward priority 0; policy drop;

        # LAN and WiFi to WAN
        iifname "br-lan" oifname "${wan}" accept comment "allow LAN to WAN"
        iifname "${wifi}" oifname "${wan}" accept comment "allow WiFi to WAN"

        # WAN to LAN/WiFi: only established/related
        iifname "${wan}" oifname "br-lan" ct state { established, related } accept comment "allow established WAN to LAN"
        iifname "${wan}" oifname "${wifi}" ct state { established, related } accept comment "allow established WAN to WiFi"

        # Log and drop everything else (rate-limited)
        counter log prefix "dropped forward: " limit rate 5/minute drop comment "log and drop other forwarded traffic"
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }

    table ip nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "${wan}" masquerade comment "NAT LAN traffic to WAN"
      }
    }
  '';
}
