{
  config,
  lib,
  ...
}: let
  inherit (lib) concatMap concatStringsSep imap0 listToAttrs map nameValuePair optionalAttrs;

  # ── The segment matrix ──────────────────────────────────────────────────────
  #
  # This is the only place a subnet, gateway, DHCP pool or port assignment is
  # written down. networkd netdevs, .network files, DHCP scopes, policy-routing
  # rules and the Tailscale advertise list are all derived from it, so they
  # cannot drift apart. The firewall reads the same option (config.vault.segments).
  #
  # Ports are matched by PCI path, not kernel name: the names enp1s0..enp6s0 are
  # assigned by udev's slot-based naming policy and would move if a card is
  # reseated or the firmware renumbers the slots. The MAC is recorded for the
  # humans and for evidence, not used for matching.
  #
  # Live cabling (2026-11-23):
  #   enp4s0 → 8-port estate switch: homelab, k3s node0-4, kube-vip, PiKVM, Traefik
  #   enp5s0 → gaming PC (Windows `myles-pc`, MAC 3c:7c:3f:1c:fc:c5)
  #   enp3s0 → AI workstation (`bee-gpu-server`, MAC d8:bb:c1:12:59:ff)
  #   wlp7s0 → `beans-test` AP (owned by hostapd, never by networkd)
  #   enp6s0 → management / break-glass (no bridge, no DHCP)
  #   enp2s0 → spare, left inert on purpose
  mat = {
    homelab = {
      bridge = "br-homelab";
      port = {
        name = "enp4s0";
        path = "pci-0000:04:00.0";
        mac = "00:e0:67:2b:bd:39";
      };
      subnet = "10.0.0.0/24";
      gateway = "10.0.0.1";
      # 10.0.0.60-89: below everything static (PiKVM .175, kube-vip .200,
      # Traefik .99, the k3s nodes .140-144, homelab .150).
      dhcpPool = {
        offset = 60;
        size = 30;
      };
      # The estate switch hangs off this bridge; STP belongs here and only here.
      stp = true;
      staticLeases = [];
    };

    gaming = {
      bridge = "br-gaming";
      port = {
        name = "enp5s0";
        path = "pci-0000:05:00.0";
        mac = "00:e0:67:2b:bd:3a";
      };
      subnet = "10.20.0.0/24";
      gateway = "10.20.0.1";
      dhcpPool = {
        offset = 20;
        size = 80;
      };
      stp = false;
      # The live host is Windows `myles-pc`; `bee-pc` is only its NixOS label.
      # A reservation keeps the Windows side on plain DHCP.
      staticLeases = [
        {
          MACAddress = "3c:7c:3f:1c:fc:c5";
          Address = "10.20.0.10";
          Hostname = "myles-pc";
        }
      ];
    };

    ai = {
      bridge = "br-ai";
      port = {
        name = "enp3s0";
        path = "pci-0000:03:00.0";
        mac = "00:e0:67:2b:bd:38";
      };
      subnet = "10.30.0.0/24";
      gateway = "10.30.0.1";
      dhcpPool = {
        offset = 20;
        size = 80;
      };
      stp = false;
      # `bee-gpu-server` is configured statically on the host with this same
      # address; the reservation keeps the address reserved even if it ever
      # falls back to DHCP.
      staticLeases = [
        {
          MACAddress = "d8:bb:c1:12:59:ff";
          Address = "10.30.0.10";
          Hostname = "bee-gpu-server";
        }
      ];
    };

    wifi = {
      bridge = "br-wifi";
      # wlp7s0 is enslaved by hostapd, not networkd. The bridge itself is a
      # netdev only; no member .network file is generated for this segment.
      port = null;
      subnet = "10.50.0.0/24";
      gateway = "10.50.0.1";
      dhcpPool = {
        offset = 20;
        size = 180;
      };
      stp = false;
      staticLeases = [];
    };
  };

  segmentModule = {
    options = {
      name = lib.mkOption {type = lib.types.str;};
      bridge = lib.mkOption {type = lib.types.str;};
      port = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            name = lib.mkOption {type = lib.types.str;};
            path = lib.mkOption {type = lib.types.str;};
            mac = lib.mkOption {type = lib.types.str;};
          };
        });
      };
      subnet = lib.mkOption {type = lib.types.str;};
      gateway = lib.mkOption {type = lib.types.str;};
      prefixLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
      };
      dhcpPool = lib.mkOption {
        type = lib.types.submodule {
          options = {
            offset = lib.mkOption {type = lib.types.int;};
            size = lib.mkOption {type = lib.types.int;};
          };
        };
      };
      stp = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      staticLeases = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            MACAddress = lib.mkOption {type = lib.types.str;};
            Address = lib.mkOption {type = lib.types.str;};
            Hostname = lib.mkOption {type = lib.types.str;};
          };
        });
        default = [];
      };
    };
  };

  # Rule priorities sit above the Tailscale-owned fwmark rules (5210-5270) so
  # Tailscale keeps its own policy, and below the kernel's main/default lookups
  # (32766/32767). Each per-segment rule is generated from the matrix index.
  ruleBase = 32760;
  matrix = [
    (mat.homelab // {name = "homelab";})
    (mat.gaming // {name = "gaming";})
    (mat.ai // {name = "ai";})
    (mat.wifi // {name = "wifi";})
  ];

  # The evaluated matrix, with a generated policy-rule priority per segment.
  segments = imap0 (i: s: s // {rulePriority = ruleBase + i;}) config.vault.segments;

  tailscaleRulePriority =
    ruleBase
    + builtins.length segments
    + 1;
in {
  options.vault = {
    segments = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule segmentModule);
      default = matrix;
      description = ''
        The LAN segment matrix. Every bridge, subnet, gateway, DHCP scope and
        policy-routing rule on the Vault is generated from this list.
      '';
    };

    mgmtSubnet = lib.mkOption {
      type = lib.types.str;
      default = "192.168.200.0/24";
      description = "Out-of-band management subnet on enp6s0. Never advertised or forwardable.";
    };

    mgmtAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.200.1/24";
      description = "The Vault's out-of-band management address on enp6s0.";
    };
  };

  config = {
    # ── netdevs: one bridge per segment ───────────────────────────────
    systemd.network.netdevs = listToAttrs (map (s:
      nameValuePair "25-${s.bridge}" {
        netdevConfig = {
          Kind = "bridge";
          Name = s.bridge;
        };
        bridgeConfig = {
          STP = s.stp;
          # One flat L2 domain per bridge, no loops except through the
          # switch. Snooping stays on; there is no cross-segment multicast.
          MulticastSnooping = true;
        };
      })
    segments);

    # ── .network files: bridge members and bridge addresses ───────────
    systemd.network.networks =
      listToAttrs (concatMap (s:
        (lib.optional (s.port != null)
          (nameValuePair "30-${s.port.name}" {
            matchConfig.Path = s.port.path;
            networkConfig = {
              Bridge = s.bridge;
              # The port itself is never addressed. No DHCP client, no
              # link-local: the address lives on the bridge.
              LinkLocalAddressing = "no";
              ConfigureWithoutCarrier = true;
            };
            linkConfig.RequiredForOnline = "enslaved";
          }))
        ++ [
          (nameValuePair "40-${s.bridge}" {
            matchConfig.Name = s.bridge;
            address = ["${s.gateway}/${toString s.prefixLength}"];
            networkConfig = {
              ConfigureWithoutCarrier = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
              DHCPServer = true;
              # segment bridges legitimately receive 100.64/10 sources only
              # from tailscale0, which is a different interface; keep the
              # reverse-path check loose for asymmetric tailnet paths.
              IPv4ReversePathFilter = "loose";
            };
            # Keep inter-segment and tailnet-to-LAN traffic in the main table;
            # otherwise `iif tailscale0 lookup 100` (whose default is wg0)
            # would swallow it. Attached to the bridge's own network, so the
            # rule disappears exactly when that segment becomes unreachable.
            routingPolicyRules = [
              {
                To = s.subnet;
                Table = 254;
                Priority = s.rulePriority;
              }
            ];
            dhcpServerConfig = {
              PoolOffset = s.dhcpPool.offset;
              PoolSize = s.dhcpPool.size;
              EmitDNS = true;
              DNS = [s.gateway];
              EmitRouter = true;
              Router = s.gateway;
              DefaultLeaseTimeSec = "12h";
              MaxLeaseTimeSec = "24h";
              PersistLeases = true;
            };
            dhcpServerStaticLeases = s.staticLeases;
            linkConfig.RequiredForOnline = "no";
          })
        ])
      segments)
      // {
        # ── Exit-node policy routing ──────────────────────────────────
        # Installed on the WAN link, which is up whenever the tailnet is
        # reachable. Keep it *after* every per-segment `to ... lookup main`
        # rule: tailnet-to-LAN resolves through main, internet-bound tailnet
        # traffic falls into table 100 and out wg0.
        "10-wan" = {
          routingPolicyRules = [
            # Unbound forwards to Mullvad's in-tunnel resolver. Scope the rule
            # to that one address: a bare `User = "unbound"` rule sent every
            # query, including the recursive fallback, into table 100, where the
            # blackhole default swallowed it whenever wg0 was down.
            {
              To = "10.64.0.1/32";
              User = "unbound";
              Table = 100;
              Priority = 32759;
            }
            {
              IncomingInterface = "tailscale0";
              Table = 100;
              Priority = tailscaleRulePriority;
            }
          ];
        };
      };

    # ── networkd must not delete state it does not own ────────────────
    # Tailscale writes table 52 and the 5210-5270 fwmark rules directly;
    # networkd reconfigures would otherwise remove them (systemd issue 41350).
    systemd.network.config.networkConfig = {
      ManageForeignRoutingPolicyRules = false;
      ManageForeignRoutes = false;
    };
  };
}
