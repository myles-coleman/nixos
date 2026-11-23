{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  lan1 = "enp2s0";
  lan2 = "enp3s0";
  lan3 = "enp4s0";
  lan4 = "enp5s0";
  mgmt = "enp6s0";
  wifi = "wlp7s0";

  # Helper: enslave a LAN interface to the br-lan bridge
  enslaveToBridge = name: {
    "30-${name}" = {
      matchConfig.Name = name;
      networkConfig = {
        Bridge = "br-lan";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "enslaved";
    };
  };
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
  # The Vault will use Pi-hole (192.168.1.1) for its own DNS after Pi-hole starts
  # Temporary bootstrap DNS is provided by Docker daemon settings
  services.resolved.enable = false;

  # Set static DNS for the Vault itself to use Pi-hole
  networking.nameservers = ["192.168.1.1" "8.8.8.8"];

  # ── IPv4 forwarding (required for routing) ─────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    # Tailscale subnet-router traffic arrives on tailscale0 with a 100.64/10
    # source while its reverse path is the WAN default; strict rp_filter drops
    # it. Keep the policy loose.
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    # br-lan is deliberately one flat L2 domain: its ports must be able to
    # reach each other without the routed-traffic forward chain dropping the
    # bridged frames. Docker loads br_netfilter, which otherwise feeds those
    # frames to `inet filter forward` (policy drop). Keep the bridge out of
    # the IP hook; the L3 rules still cover everything that is routed.
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
  };

  # Docker sets the bridge sysctls when it starts, after systemd-sysctl.
  # Re-assert them after Docker (and whenever Docker restarts).
  systemd.services.flat-bridge-netfilter = {
    description = "Keep the flat br-lan bridge out of the IP forward chain";
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

    # ── Bridge netdev ──────────────────────────────────────────────
    netdevs = {
      "20-br-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-lan";
        };
      };
    };

    # ── Network configurations ─────────────────────────────────────
    networks =
      # Enslave LAN interfaces to the bridge
      lib.mergeAttrsList (map enslaveToBridge [lan1 lan2 lan3 lan4])
      // {
        # WAN: DHCP from the Hitron CODA56 modem-only bridge. The old static
        # address (10.0.0.227/24) was a workaround for the Xfinity gateway
        # dropping DHCP on 2026-10-28; the CODA56 is the edge now and leases a
        # public address. The 192.168.100.2/24 alias is for the modem's
        # source-restricted status GUI at 192.168.100.1.
        "10-wan" = {
          matchConfig.Name = wan;
          address = ["192.168.100.2/24"];
          networkConfig = {
            DHCP = "ipv4";
            IPv4Forwarding = true;
          };
          dhcpV4Config = {
            UseDNS = true;
            UseRoutes = true;
          };
          linkConfig.RequiredForOnline = "routable";
        };

        # Management port: separate subnet for SSH safety
        "10-mgmt" = {
          matchConfig.Name = mgmt;
          address = ["192.168.200.1/24"];
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "no";
        };

        # LAN bridge: main internal network
        #
        # Policy routing for the Mullvad tunnel lives on this *persistent*
        # link, not on wg0: networkd drops rules attached to a link when it
        # goes down. Table 100 must stay in sync with
        # hosts/protecli-vault/modules/mullvad.nix (wgTable).
        "40-br-lan" = {
          matchConfig.Name = "br-lan";
          # Transitional dual-subnet bridge: 192.168.1.0/24 carries the
          # operator laptop and the AI server; 10.0.0.0/24 is the estate's
          # preserved addressing (homelab, k3s, PiKVM, kube-vip). The
          # segmentation spec later splits 10.0.0.0/24 into its own bridges.
          address = ["192.168.1.1/24" "10.0.0.1/24"];
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
          routingPolicyRules = [
            # Keep inter-subnet and tailnet-to-LAN traffic out of table 100
            # (whose default is wg0). These must precede the table-100 rules.
            {
              To = "10.0.0.0/24";
              Table = 254;
              Priority = 32761;
            }
            {
              To = "192.168.1.0/24";
              Table = 254;
              Priority = 32762;
            }
            # LAN clients: AND the source subnet with the ingress interface
            # so the Vault's own 192.168.1.1 host traffic is NOT matched.
            {
              From = "192.168.1.0/24";
              IncomingInterface = "br-lan";
              Table = 100;
            }
            # Tailnet clients using the Vault as exit node / subnet router.
            {
              IncomingInterface = "tailscale0";
              Table = 100;
            }
          ];
          routes = [
            # LAN-destined tailnet traffic (subnet routing) must leave via
            # br-lan, not the table-100 default (wg0). Without this, an
            # advertised 192.168.1.0/24 route would be tunneled into Mullvad.
            {
              Destination = "192.168.1.0/24";
              Table = 100;
              Scope = "link";
            }
            # Persistent blackhole: when wg0 is down its metric-0 default
            # disappears and this catches the lookup instead of falling
            # through to main -> WAN.
            {
              Destination = "0.0.0.0/0";
              Table = 100;
              Metric = 1000;
              Type = "blackhole";
            }
          ];
          linkConfig.RequiredForOnline = "no";
        };
      };
  };
}
