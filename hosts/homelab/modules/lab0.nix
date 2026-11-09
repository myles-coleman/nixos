{
  config,
  pkgs,
  lib,
  ...
}: let
  # Every lab0 bridge port uses this prefix. nftables matches the *port*
  # (e.g. tap-lab0-broker), not the bridge device, because a packet entering a
  # bridge port carries that port as `iifname`.
  labPorts = "tap-lab0-*";

  redteamLabRules = pkgs.writeText "redteam-lab.nft" ''
    table inet redteam_lab {
      chain forward {
        type filter hook forward priority -150; policy drop;

        # Preserve every non-lab forwarding path (Docker, br0<->br0). Traffic
        # that enters or leaves a lab0 port falls through to the drop policy.
        iifname != "${labPorts}" oifname != "${labPorts}" accept
      }

      chain input {
        type filter hook input priority -150; policy accept;

        # Nothing on the lab may reach the hypervisor itself. This closes the
        # hole a forward-only filter leaves for locally delivered traffic.
        iifname "${labPorts}" drop
      }
    }
  '';
in {
  # ── lab0: the isolated red-team target plane (spec 31, Unit 2) ─────────────
  #
  # A bridge with no uplink, no host L3 address, and no NAT. The boundary is
  # the explicit nftables policy below, not the absence of an address. The APTS
  # assessment's F1 is the precedent: `policy accept` is not a boundary.
  #
  # NetworkManager owns the bridge, matching the existing br0 pattern. The tap
  # ports are created by a separate oneshot because microvm.nix's `tap` type
  # expects the interface to exist and does not attach it to a bridge.
  networking.networkmanager.ensureProfiles.profiles.lab0 = {
    connection = {
      id = "lab0";
      type = "bridge";
      interface-name = "lab0";
      autoconnect = "true";
    };
    ipv4.method = "disabled";
    ipv6.method = "disabled";
    bridge = {
      stp = "false";
      forward-delay = "0";
    };
  };

  # NetworkManager re-activates lab0 after the oneshot has run, which resets
  # the per-interface sysctls to the global forwarding default. Apply them on
  # every `up` event, not just once at boot.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeScript "50-redteam-lab" ''
        #!/bin/sh
        if [ "$1" = "lab0" ] && [ "$2" = "up" ]; then
          ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.lab0.forwarding=0
          ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.lab0.disable_ipv6=1
          ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.lab0.accept_ra=0
        fi
      '';
    }
  ];

  # Create the deterministic tap ports and attach them to their bridges. The
  # names are load-bearing: the nftables boundary matches `tap-lab0-*`, and
  # microvm.nix uses the `id` as the host interface name for `type = "tap"`.
  systemd.services.redteam-lab-taps = {
    description = "Create and attach the red-team lab tap devices (spec 31)";
    wants = ["NetworkManager.service"];
    after = ["NetworkManager.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.iproute2 pkgs.procps];
    script = ''
      set -eu

      # NetworkManager creates lab0 asynchronously; wait for it before
      # attaching ports so a boot does not race the bridge.
      for _ in $(seq 1 30); do
        ip link show lab0 >/dev/null 2>&1 && break
        sleep 1
      done
      ip link show lab0 >/dev/null 2>&1 || {
        echo "lab0 did not appear" >&2
        exit 1
      }
      ip link set lab0 up

      for tap in tap-lab0-broker tap-lab0-target; do
        ip link show "$tap" >/dev/null 2>&1 \
          || ip tuntap add dev "$tap" mode tap user microvm
        # The bridge recomputes its forwarding value from its ports when a
        # port is attached. Set the port to 0 first so lab0 stays at 0.
        sysctl -w net.ipv4.conf."$tap".forwarding=0
        ip link set "$tap" up
        ip link set "$tap" master lab0
      done

      # The broker's control leg shares br0. It is a tap, not a microvm.nix
      # `bridge` interface, so QEMU's seccomp sandbox stays enabled.
      ip link show tap-br0-broker >/dev/null 2>&1 \
        || ip tuntap add dev tap-br0-broker mode tap user microvm
      ip link set tap-br0-broker up
      ip link set tap-br0-broker master br0

      # Per-interface sysctls must be applied after the interface exists; the
      # boot-time sysctl service runs before NetworkManager creates lab0.
      sysctl -w net.ipv4.conf.lab0.forwarding=0
      sysctl -w net.ipv6.conf.lab0.disable_ipv6=1
      sysctl -w net.ipv6.conf.lab0.accept_ra=0
    '';
  };

  systemd.services.redteam-lab-firewall = {
    description = "Load the red-team lab nftables boundary (spec 31)";
    wants = ["redteam-lab-taps.service"];
    after = ["redteam-lab-taps.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.nftables}/bin/nft delete table inet redteam_lab 2>/dev/null || true
      ${pkgs.nftables}/bin/nft -f ${redteamLabRules}
    '';
  };
}
