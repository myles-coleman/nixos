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
  # ca-van-wg-201 (104.193.135.196) stopped forwarding on 2026-11-24: the
  # handshake stayed fresh and Mullvad's API still reported it active, but
  # nothing it received reached the internet, so every exit-node client lost
  # connectivity while the Vault itself (direct WAN) looked fine. Moved to
  # us-sea-wg-001, which is a short hop away.
  mullvadServerIp = "138.199.43.91";
  mullvadPort = 51820;
  mullvadEndpoint = "${mullvadServerIp}:${toString mullvadPort}";
  mullvadTunnelAddress = "10.68.169.78";
  mullvadPeerPublicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";

  # Dedicated routing table and firewall mark for the Mullvad tunnel.
  # NOTE: wgFwMark is a routing/firewall mark, NOT the endpoint port; the two
  # only coincide numerically here by coincidence.
  # Table 100 also carries the tailnet's 100.64.0.0/10 route; the policy rule
  # that steers `iif tailscale0` into it is generated in segments.nix, and the
  # firewall's tailscale0 -> wg0 path is in firewall.nix.
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

  # ── Table 100: fail-closed default ────────────────────────────────
  # The blackhole/unreachable default lives on the WAN network (networking.nix),
  # not here: networkd removes a .network file's routes when its link goes down,
  # so a blackhole attached to wg0 vanished exactly when it was needed. On the
  # WAN it persists, and `Type = "unreachable"` makes a failed forwarder return
  # an error immediately instead of hanging until a timeout.
  #
  # ── Table 100: return path to the tailnet ─────────────────────────
  # `iif tailscale0 lookup 100` hands every tailnet-sourced packet to table
  # 100, whose default is wg0. Tailnet-destined traffic needs its own route
  # back out tailscale0, or a tailnet-to-tailnet packet would be pulled into
  # the Mullvad tunnel.
  #
  # networkd cannot declare this: routes in a .network file are bound to that
  # file's link, and tailscale0 is unmanaged (Tailscale creates it with
  # --netfilter-mode=off). A tiny oneshot keeps the route idempotent instead.
  systemd.services.tailnet-table100-route = {
    description = "Keep the tailnet return route in routing table 100";
    wantedBy = ["multi-user.target"];
    requires = ["sys-subsystem-net-devices-tailscale0.device"];
    after = [
      "sys-subsystem-net-devices-tailscale0.device"
      "systemd-networkd.service"
      "tailscaled.service"
    ];
    wants = ["tailscaled.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    # tailscale0 exists as soon as the device unit is plugged, but it stays
    # down (no carrier) until tailscaled finishes configuring it, and
    # `ip route replace` refuses a nexthop whose device is down. Retry until
    # the route is actually accepted instead of guessing at the link state.
    script = ''
      for _ in $(seq 1 90); do
        if ${pkgs.iproute2}/bin/ip route replace 100.64.0.0/10 dev tailscale0 table ${toString wgTable} 2>/dev/null; then
          exit 0
        fi
        sleep 1
      done
      echo "tailscale0 did not come up within 90s" >&2
      exit 1
    '';
  };
}
