{
  config,
  pkgs,
  lib,
  ...
}: let
  # ── Mullvad endpoint configuration ─────────────────────────────────
  # Values taken from the Mullvad WireGuard configuration generator.
  # To change Mullvad location, edit `mullvadServerIp` and rebuild. To use a
  # different UDP port, edit `mullvadPort` (it must be a port the chosen relay
  # accepts; 51820 is the generator default, but 53/1234/443/5001 also work).
  # The WireGuard key and tunnel address work across all Mullvad servers, so
  # no new key registration is required.
  #
  # The generated config's IPv6 address and `DNS = 10.64.0.1` are intentionally
  # not used: IPv6 is blackholed, and DNS stays local (Pi-hole + recursive
  # Unbound) to avoid the 100.64.0.0/10 CGNAT collision with Tailscale.
  mullvadServerIp = "104.193.135.196";
  mullvadPort = 51820;
  mullvadEndpoint = "${mullvadServerIp}:${toString mullvadPort}";
  mullvadTunnelAddress = "10.68.169.78";
  mullvadPeerPublicKey = "hYbb2NQKB0g2RefngdHl3bfaLImUuzeVIv2i1VCVIlQ=";

  # Dedicated routing table and firewall mark for the Mullvad tunnel.
  # NOTE: wgFwMark is a routing/firewall mark, NOT the endpoint port; the two
  # only coincide numerically here by coincidence.
  # These MUST stay in sync with hosts/protecli-vault/modules/networking.nix
  # (the persistent policy rules on br-lan) and modules/firewall.nix.
  wgTable = 100;
  wgFwMark = 51820;

  wgKeyPath = config.sops.secrets.mullvad_wg_private_key.path;
in {
  # ── sops-managed WireGuard private key ─────────────────────────────
  # systemd-networkd reads this file directly, so it must be readable by
  # the systemd-network user. The key never lands in the Nix store.
  sops.secrets.mullvad_wg_private_key = {
    owner = "systemd-network";
    group = "systemd-network";
    mode = "0640";
    restartUnits = ["systemd-networkd.service"];
  };

  systemd.network = {
    # ── wg0 netdev ───────────────────────────────────────────────────
    netdevs."30-wg0" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg0";
        MTUBytes = 1420;
      };
      wireguardConfig = {
        PrivateKeyFile = wgKeyPath;
        FirewallMark = wgFwMark;
        # Do not let networkd add the AllowedIPs routes to the main table;
        # the default route is added explicitly to table 100 below.
        RouteTable = "off";
      };
      wireguardPeers = [
        {
          PublicKey = mullvadPeerPublicKey;
          Endpoint = mullvadEndpoint;
          AllowedIPs = ["0.0.0.0/0"];
          RouteTable = "off";
          PersistentKeepalive = 25;
        }
      ];
    };

    # ── wg0 network ──────────────────────────────────────────────────
    networks."30-wg0" = {
      matchConfig.Name = "wg0";
      address = ["${mullvadTunnelAddress}/32"];
      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = "0.0.0.0";
          Table = wgTable;
          Metric = 0;
        }
      ];
      linkConfig.RequiredForOnline = "no";
    };
  };
}
