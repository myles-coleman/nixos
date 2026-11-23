{
  config,
  pkgs,
  lib,
  ...
}: let
  wan = "enp1s0";
  mgmt = "enp6s0";

  inherit (lib) concatMapStrings concatStringsSep map;

  # Everything below is derived from the one segment matrix in segments.nix.
  segments = config.vault.segments;
  segmentBridges = map (s: s.bridge) segments;
  segmentSubnets = map (s: s.subnet) segments;
  bridgeSet = "{ ${concatStringsSep ", " (map (b: "\"${b}\"") segmentBridges)} }";

  # Anti-spoofing: a port that belongs to one segment may only carry that
  # segment's subnet. Logged (rate-limited) so a forged source is visible.
  antiSpoof =
    concatMapStrings (s: ''
      iifname "${s.bridge}" ip saddr != ${s.subnet} counter log prefix "anti-spoof ${s.bridge}: " limit rate 5/minute drop comment "anti-spoof ${s.name} segment"
    '')
    segments;

  tailnetToSegments =
    concatMapStrings (s: ''
      iifname "tailscale0" oifname "${s.bridge}" accept comment "tailnet to ${s.name} (subnet routing)"
      iifname "${s.bridge}" oifname "tailscale0" accept comment "${s.name} to tailnet (subnet routing)"
    '')
    segments;

  segmentToWan =
    concatMapStrings (s: ''
      iifname "${s.bridge}" oifname "${wan}" accept comment "${s.name} direct WAN"
    '')
    segments;

  # The AI workstation's address comes from the AI segment's static lease in
  # the matrix; the allow matrix below must not carry a second copy of it.
  aiSegment = lib.findFirst (s: s.name == "ai") (throw "segments.nix: no `ai` segment in the matrix") segments;
  aiHost = (builtins.head aiSegment.staticLeases).Address;
  aiPort = 8080;

  # The Vault's own services that a segment client is allowed to reach.
  # 80/443 are the Pi-hole admin UI, 22 is key-only SSH, 53 DNS, 67 DHCP,
  # 123 NTP; ICMP for path MTU and reachability.
  toRouter = ''
    iifname ${bridgeSet} udp dport { 53, 67, 123 } accept comment "segment DNS/DHCP/NTP to the router"
    iifname ${bridgeSet} tcp dport { 22, 53, 80, 443 } accept comment "segment SSH/DNS/Pi-hole admin to the router"
    iifname ${bridgeSet} icmp type { echo-request, destination-unreachable, time-exceeded } accept comment "segment ICMP to the router"
  '';
in {
  networking.nftables.enable = true;
  networking.nftables.checkRuleset = false;
  networking.firewall.enable = lib.mkForce false;

  networking.nftables.ruleset = ''
    table inet filter {
      set segment_prefixes {
        type ipv4_addr
        flags interval
        comment "the four LAN segment prefixes, generated from segments.nix"
        elements = {
          ${concatStringsSep ", " segmentSubnets}
        }
      }

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

        # Return traffic for host-initiated connections (recursive Unbound
        # queries and their replies, nix, NTP, the tailscaled control plane).
        ct state { established, related } accept comment "allow established/related input"

        # Segment clients to the router: only the services they need.
        ${toRouter}

        # Tailscale: --netfilter-mode=off means the Vault owns the path,
        # so accept tailnet input and the Tailscale transport port here.
        iifname "tailscale0" accept comment "allow Tailscale input"
        # With --netfilter-mode=off the Vault must accept the Tailscale
        # transport port itself; it arrives on the WAN interface, not tailscale0.
        udp dport 41641 accept comment "allow Tailscale transport"

        # Mullvad tunnel: accept return traffic for exit-node clients and for
        # the Vault's own host traffic.
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

        # ── Anti-spoofing, before anything can be accepted ───────────
        ${antiSpoof}

        # ── Management plane: break-glass in, nothing back in ────────
        iifname "${mgmt}" accept comment "management to anywhere (break-glass)"
        iifname != "${mgmt}" ip daddr ${config.vault.mgmtSubnet} drop comment "segments and tailnet cannot reach management"

        # ── The allow matrix ─────────────────────────────────────────
        # Everything not listed here stays denied by the policy drop.
        # gaming -> AI inference only.
        iifname "br-gaming" oifname "br-ai" ip daddr ${aiHost} tcp dport ${toString aiPort} accept comment "gaming to AI inference (tcp/${toString aiPort})"

        # ── Tailnet subnet routing ───────────────────────────────────
        ${tailnetToSegments}

        # ── Media egress overlay (tag:media-egress) ───────────────────
        # qBittorrent and Prowlarr reach the internet as tailnet exit-node
        # clients: tailscale0 -> wg0, and the replies back. Their own pod
        # kill switches fail closed if this path is gone.
        iifname "tailscale0" oifname "wg0" accept comment "tailnet exit-node clients to Mullvad"
        iifname "wg0" oifname "tailscale0" accept comment "Mullvad replies to tailnet clients"

        # ── Bogon egress filter, before any WAN accept ───────────────
        # A LAN prefix must never be routed out the WAN, even if a segment is
        # re-addressed into public space: this is the matrix-generated half.
        oifname "${wan}" ip daddr @segment_prefixes counter drop comment "no segment prefix egresses the WAN"
        oifname "${wan}" ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } counter drop comment "no bogon egresses the WAN"

        # ── Direct WAN egress for every segment ──────────────────────
        ${segmentToWan}

        # ── The single kill switch ───────────────────────────────────
        # Only exit-node traffic may reach the internet from the tailnet, and
        # that goes through wg0 above. There is exactly one such rule.
        iifname "tailscale0" oifname "${wan}" drop comment "HARD KILL SWITCH: no tailnet WAN fallback"

        # IPv6 is actively blackholed, not merely ignored.
        meta nfproto ipv6 drop comment "IPv6 blackholed"

        # CGNAT anti-spoof for forwarded traffic.
        iifname != "tailscale0" ip saddr 100.64.0.0/10 drop comment "CGNAT anti-spoof"

        # Return traffic for the above flows.
        ct state { established, related } accept comment "allow return traffic"

        # Log and drop everything else: inter-segment traffic that is not in
        # the allow matrix lands here.
        counter log prefix "dropped forward: " limit rate 5/minute drop comment "default deny: log and drop other forwarded traffic"
      }

      chain output {
        type filter hook output priority 0; policy accept;

        # WireGuard's own encapsulated packets carry the tunnel fwmark.
        # Exempt them explicitly so a future output-chain rule cannot drop the
        # tunnel's transport packets.
        meta mark 51820 accept comment "allow WireGuard encapsulated packets"

        # Spec 29, Unit 1: Unbound resolves by full recursion out the WAN, so
        # there is deliberately no `skuid unbound` WAN drop here any more.
      }
    }

    table ip nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "wg0" masquerade comment "NAT exit-node clients into the Mullvad tunnel"
        oifname "tailscale0" masquerade comment "SNAT LAN traffic leaving via the tailnet"
        # Tailnet -> segment traffic is SNATed to that segment's gateway before
        # it reaches the host. Tailscale's own netfilter mode installs exactly
        # this (its ts-postrouting MASQUERADE); the Vault runs
        # `--netfilter-mode=off`, so it has to do it itself. Without it, a
        # destination host that also runs Tailscale routes its reply to the
        # 100.x source out of its own tailscale0 with a foreign source address
        # (e.g. 10.0.0.200), which tailscaled drops: the handshake never
        # completes and any tailnet->kube-vip client (CI's kubeconfig to
        # 10.0.0.200:6443) times out.
        iifname "tailscale0" oifname ${bridgeSet} masquerade comment "SNAT tailnet-to-segment traffic"
        oifname "${wan}" masquerade comment "NAT segments and the Vault to the WAN"
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
