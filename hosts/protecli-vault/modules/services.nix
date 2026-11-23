{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── Unbound NixOS Service (Recursive DNS Resolver) ─────────────────
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = ["127.0.0.1"];
        port = 5335;
        access-control = ["127.0.0.0/8 allow"];
        do-not-query-localhost = false;

        # DNSSEC validation (auto-trust-anchor-file is set automatically by NixOS)
        verbosity = 1;
        num-threads = 2; # Match i5-7200U's 2 cores

        # IPv6 is actively blackholed on the Vault; make sure Unbound never
        # tries to resolve over it.
        do-ip6 = false;

        # Security hardening
        hide-identity = true;
        hide-version = true;
      };

      # Forward to Mullvad's in-tunnel resolver (10.64.0.1) so queries travel
      # inside wg0: the ISP sees WireGuard, not plaintext DNS names, and the
      # resolver a site sees is Mullvad's. The policy rule that puts the
      # unbound user into table 100 lives in networking.nix.
      #
      # `forward-first: yes` is the point of this design: if wg0 is down the
      # forwarder times out and Unbound falls back to full recursion out the
      # WAN. A tunnel outage therefore costs privacy for the duration, not DNS
      # for the house -- the failure mode spec 29 Unit 1 set out to remove.
      #
      # DNSSEC validation and the trust anchor stay on, so a hijacked answer
      # that fails validation is served as SERVFAIL, not silently accepted.
      forward-zone = [
        {
          name = ".";
          forward-addr = "10.64.0.1";
          forward-first = true;
        }
      ];
    };
  };

  # ── Pi-hole Docker Container (DHCP + DNS with ad blocking) ─────────
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      pihole = {
        image = "pihole/pihole@sha256:f7d1be836e3bc608b56d82fc9904f5a831cdfbc0dc9c6d58f94e4c985c70038b";
        extraOptions = [
          "--network=host"
          "--cap-add=NET_ADMIN"
        ];
        environment = {
          TZ = "America/Los_Angeles";
          WEBPASSWORD = ""; # Empty -- set manually post-deploy for security

          # Pi-hole v6 Configuration via FTLCONF_ environment variables
          #
          # `dns.interface` is pinned in pihole.toml (it was "br-lan" ### CHANGED
          # (env)). Deleting the env var does NOT revert the stored value, so set
          # it to the empty string explicitly: FTL then listens on all
          # interfaces, which is what dns.listeningMode=ALL already does.
          # DHCP now belongs to systemd-networkd on each segment bridge.
          FTLCONF_dns_interface = "";
          FTLCONF_dns_upstreams = "127.0.0.1#5335";
          FTLCONF_dns_domain_name = "lan";
          FTLCONF_dns_listeningMode = "ALL";

          # dhcp.active was persisted as true; removing the variable would not
          # stop the server. Turn it off explicitly so exactly one DHCP
          # authority (networkd) remains per bridge.
          FTLCONF_dhcp_active = "false";
        };
        volumes = [
          "/var/lib/pihole/etc-pihole:/etc/pihole"
          "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
        ];
      };
    };
  };

  # ── Create Pi-hole persistent data directories ─────────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/pihole/etc-pihole 0755 root root -"
    "d /var/lib/pihole/etc-dnsmasq.d 0755 root root -"
  ];

  # ── Service dependencies: Unbound starts before Pi-hole ────────────
  systemd.services.docker-pihole = {
    after = ["unbound.service"];
    requires = ["unbound.service"];
  };
}
