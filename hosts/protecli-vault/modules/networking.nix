{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  mgmt = "enp6s0";

  mgmtRulePriority = 32764;
in {
  # ── Use systemd-networkd (not NetworkManager) ──────────────────────
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce false;
  networking.networkmanager.enable = false;

  # ── Disable default NixOS firewall and NAT modules ─────────────────
  # All firewall/NAT rules are managed via nftables in firewall.nix
  networking.firewall.enable = lib.mkForce false;
  networking.nat.enable = false;

  # ── Disable systemd-resolved entirely ──────────────────────────────
  # The Vault resolves through its own Pi-hole (127.0.0.1:53), which fronts
  # the recursive Unbound on 127.0.0.1:5335.
  services.resolved.enable = false;

  # Bootstrap fallback only: Pi-hole may not be up yet when the Vault needs a
  # name (nix substituters, NTP). 8.8.8.8 is a last resort, not an upstream.
  networking.nameservers = ["127.0.0.1" "8.8.8.8"];

  # ── IPv4 forwarding (required for routing) ─────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    # Tailscale subnet-router traffic arrives on tailscale0 with a 100.64/10
    # source while its reverse path is the WAN default; strict rp_filter drops
    # it. Keep the policy loose (each segment bridge also sets
    # IPv4ReversePathFilter=loose in the generated .network file).
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    # Every bridge is one flat L2 domain: its ports must reach each other
    # without the routed-traffic forward chain dropping the bridged frames.
    # Docker loads br_netfilter, which otherwise feeds those frames to
    # `inet filter forward` (policy drop). Keep the bridge out of the IP hook;
    # the L3 rules still cover everything that is routed between segments.
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
  };

  # Docker sets the bridge sysctls when it starts, after systemd-sysctl.
  # Re-assert them after Docker (and whenever Docker restarts).
  systemd.services.bridge-netfilter-off = {
    description = "Keep the segment bridges out of the IP forward chain";
    wantedBy = ["multi-user.target"];
    after = ["docker.service" "systemd-modules-load.service"];
    partOf = ["docker.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-iptables=0
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-ip6tables=0
    '';
  };

  # ── Allow interfaces to be plugged/unplugged dynamically ───────────
  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    # The segment bridges, their member ports, addresses, DHCP scopes and
    # per-segment policy rules are generated from the matrix in segments.nix.
    networks = {
      # WAN: DHCP from the Hitron CODA56 modem-only bridge. The 192.168.100.2/24
      # alias is for the modem's source-restricted status GUI at 192.168.100.1.
      # (The `iif tailscale0 lookup 100` policy rule is attached to this network
      # in segments.nix, because it must exist whenever the tailnet is usable.)
      "10-wan" = {
        matchConfig.Name = wan;
        address = ["192.168.100.2/24"];
        networkConfig = {
          DHCP = "ipv4";
          IPv4Forwarding = true;
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS = true;
          UseRoutes = true;
        };
        routes = [
          # Fail-closed default for routing table 100. It must live on a link
          # that stays up: networkd drops a network's routes when its link goes
          # down, and wg0 is exactly the link that fails. `unreachable` (rather
          # than a silent blackhole) makes Unbound's in-tunnel forwarder fail
          # instantly, so `forward-first` falls back to recursion without a
          # multi-second stall - and the query never leaks out the WAN.
          {
            Destination = "0.0.0.0/0";
            Table = 100;
            Metric = 1000;
            Type = "unreachable";
          }
        ];
        linkConfig.RequiredForOnline = "routable";
      };

      # Management port: separate subnet for SSH safety. No bridge, no DHCP:
      # the break-glass laptop is configured by hand at 192.168.200.2/24.
      "10-mgmt" = {
        matchConfig.Name = mgmt;
        address = [config.vault.mgmtAddress];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        # Tailnet-to-management traffic must never fall into table 100 (wg0).
        # The firewall drops it as well; this is the routing half.
        routingPolicyRules = [
          {
            To = config.vault.mgmtSubnet;
            Table = 254;
            Priority = mgmtRulePriority;
          }
        ];
        linkConfig.RequiredForOnline = "no";
      };
    };

    # The spare port (enp2s0) is deliberately inert: no address, no DHCP
    # client, no link-local. It is *not* left unmatched, because NixOS would
    # otherwise hand it the generated `99-ethernet-default-dhcp` catch-all
    # (only absent because networking.useDHCP is off) or the kernel would add
    # an IPv6 link-local as soon as a cable appears. An explicit match pins the
    # intent instead of relying on the catch-all's absence.
    networks."10-spare-enp2s0" = {
      matchConfig.Path = "pci-0000:02:00.0";
      networkConfig = {
        ConfigureWithoutCarrier = true;
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "no";
    };
  };
}
