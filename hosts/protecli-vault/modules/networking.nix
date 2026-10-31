{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  # Static WAN addressing on the upstream LAN. See the 10-wan block below for
  # why this is not DHCP.
  wanAddress = "10.0.0.227/24";
  wanGateway = "10.0.0.1";
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
        # WAN: statically addressed on the upstream LAN.
        #
        # This was DHCP until 2026-10-28, when the Xfinity gateway stopped
        # answering DISCOVERs (no OFFER was ever returned; other clients on the
        # same segment went unanswered too). That left the Vault with no
        # default route, no DNS, no wg0 handshake, and the hard kill switch
        # holding every client offline -- a router should not need an upstream
        # DHCP server in order to boot. The address the gateway used to lease
        # (10.0.0.227, verified unused before pinning) is now static.
        #
        # If the upstream subnet moves, update wanAddress/wanGateway above and
        # the 10.0.0.0/24 route below together.
        "10-wan" = {
          matchConfig.Name = wan;
          address = [wanAddress];
          networkConfig = {
            IPv4Forwarding = true;
          };
          # Use upstream DNS servers for the Vault itself (before Pi-hole is running)
          dns = ["8.8.8.8" "1.1.1.1"];
          routes = [
            # Default route for the Vault's own host traffic (main table).
            {
              Destination = "0.0.0.0/0";
              Gateway = wanGateway;
            }
            # Transitional: the upstream LAN (10.0.0.0/24) is advertised as a
            # tailnet subnet route, so tailnet traffic to it must leave via the
            # WAN interface instead of the table-100 default (wg0).
            {
              Destination = "10.0.0.0/24";
              Table = 100;
              Scope = "link";
            }
          ];
          linkConfig.RequiredForOnline = "routable";
        };

        # Management port: separate subnet for SSH safety
        "10-mgmt" = {
          matchConfig.Name = mgmt;
          address = ["192.168.100.1/24"];
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
          address = ["192.168.1.1/24"];
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
          routingPolicyRules = [
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
            # Locally generated recursive Unbound DNS.
            {
              User = "unbound";
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
