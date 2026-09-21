{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  mgmt = "enp6s0";
  wifi = "wlp7s0";

  # Unbound runs as the `unbound` user. NixOS may assign that uid dynamically,
  # so fall back to the user name (nft resolves names at ruleset load time).
  unboundUid = config.users.users.unbound.uid;
  unboundMatch =
    if unboundUid == null
    then "\"unbound\""
    else toString unboundUid;
in {
  networking.nftables.enable = true;
  networking.nftables.checkRuleset = false;
  networking.firewall.enable = lib.mkForce false;

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

        # CGNAT anti-spoof: Tailscale normally installs this; we must, too.
        # Kept before the general established accept so spoofed packets cannot
        # ride an existing conntrack entry.
        iifname != "tailscale0" ip saddr 100.64.0.0/10 drop comment "CGNAT anti-spoof"

        # Return traffic for host-initiated connections (e.g. Unbound queries
        # that egress via wg0 and recursive replies that arrive back on wg0).
        ct state { established, related } accept comment "allow established/related input"

        # LAN and WiFi traffic to router
        iifname "br-lan" accept comment "allow LAN traffic to router"
        iifname "${wifi}" accept comment "allow WiFi traffic to router"

        # Tailscale: --netfilter-mode=off means the Vault owns the path,
        # so accept tailnet input and the Tailscale transport port here.
        iifname "tailscale0" accept comment "allow Tailscale input"
        iifname "tailscale0" udp dport 41641 accept comment "allow Tailscale transport"

        # Mullvad tunnel: accept return traffic for the Vault's own host
        # traffic (Unbound DNS, nix, NTP, tailscaled control plane).
        iifname "wg0" accept comment "allow Mullvad tunnel input to the host"

        # WAN: only established/related connections
        iifname "${wan}" ct state { established, related } accept comment "allow established WAN traffic"

        # WAN: select ICMP types
        iifname "${wan}" icmp type { echo-request, destination-unreachable, time-exceeded } counter accept comment "allow select ICMP from WAN"

        # WAN: log and drop everything else (rate-limited)
        iifname "${wan}" counter log prefix "dropped: " limit rate 5/minute drop comment "log and drop all other WAN input"
      }

      chain forward {
        type filter hook forward priority 0; policy drop;

        # HARD KILL SWITCH: forwarded client/tailnet traffic never falls back
        # to the WAN, regardless of tunnel state.
        iifname { "br-lan", "tailscale0" } oifname "${wan}" drop comment "HARD KILL SWITCH: no WAN fallback"

        # IPv6 is actively blackholed, not merely ignored.
        meta nfproto ipv6 drop comment "IPv6 blackholed"

        # CGNAT anti-spoof for forwarded traffic.
        iifname != "tailscale0" ip saddr 100.64.0.0/10 drop comment "CGNAT anti-spoof"

        # Client/tailnet egress through the Mullvad tunnel.
        iifname { "br-lan", "tailscale0" } oifname "wg0" accept comment "clients/tailnet to Mullvad"
        iifname "wg0" oifname "br-lan" accept comment "Mullvad return to LAN"
        iifname "wg0" oifname "tailscale0" accept comment "Mullvad return to tailnet"

        # Subnet routing between the tailnet and the LAN.
        iifname "tailscale0" oifname "br-lan" accept comment "tailnet to LAN (subnet routing)"
        iifname "br-lan" oifname "tailscale0" accept comment "LAN to tailnet (subnet routing replies)"

        # Return traffic for the above flows.
        ct state { established, related } accept comment "allow return traffic"

        # Log and drop everything else (rate-limited)
        counter log prefix "dropped forward: " limit rate 5/minute drop comment "log and drop other forwarded traffic"
      }

      chain output {
        type filter hook output priority 0; policy accept;

        # WireGuard's own encapsulated packets inherit the sending socket's
        # uid and carry the tunnel fwmark. Exempt them, otherwise the
        # uid-scoped DNS kill switch below drops the tunnel itself for
        # Unbound (its queries would never leave the box).
        meta mark 51820 accept comment "allow WireGuard encapsulated packets"

        # HARD KILL SWITCH: locally generated recursive DNS must not leak to
        # the WAN when wg0 is down.
        oifname "${wan}" meta skuid ${unboundMatch} drop comment "HARD KILL SWITCH: Unbound DNS cannot leak to WAN"
      }
    }

    table ip nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "wg0" masquerade comment "NAT client traffic into the Mullvad tunnel"
        oifname "tailscale0" masquerade comment "SNAT tailnet exit/subnet traffic"
        oifname "${wan}" masquerade comment "NAT Vault host traffic to WAN"
      }
    }

    table inet mss {
      chain forward {
        type filter hook forward priority mangle; policy accept;
        oifname "wg0" tcp flags syn tcp option maxseg size set 1360 comment "MSS clamp for Mullvad tunnel"
        oifname "tailscale0" tcp flags syn tcp option maxseg size set 1380 comment "MSS clamp for tailnet"
      }
    }
  '';
}
