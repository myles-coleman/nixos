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
  wifi = "wlp7s0";
  mgmt = "enp6s0";

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
      lib.mergeAttrsList (map enslaveToBridge [lan1 lan2 lan3 lan4 wifi])
      // {
        # WAN: DHCP from upstream ISP router
        "10-wan" = {
          matchConfig.Name = wan;
          networkConfig = {
            DHCP = "ipv4";
            IPv4Forwarding = true;
          };
          # Use upstream DNS servers for the Vault itself (before Pi-hole is running)
          dns = ["8.8.8.8" "1.1.1.1"];
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
        "40-br-lan" = {
          matchConfig.Name = "br-lan";
          address = ["192.168.1.1/24"];
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
      };
  };
}
