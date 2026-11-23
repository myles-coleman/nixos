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

      # Full recursion from the root servers, deliberately with no
      # `forward-zone`. The old forwarder was 10.64.0.1 inside the Mullvad
      # tunnel, which made every DNS lookup depend on wg0 staying up.
      # Outbound port 53 from the WAN was proven open before this change
      # (`dig @198.41.0.4 . NS`). Accepted trade-off: the ISP can now see the
      # queries. See spec 29, Unit 1.
      #
      # Manual fallback if recursion ever breaks: add back
      #   forward-zone: name "." forward-addr 10.64.0.1
      # and a table-100 policy rule for the unbound user.
      # DNSSEC validation and the trust anchor stay on, so a hijacked answer
      # that fails validation is served as SERVFAIL, not silently accepted.
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
          FTLCONF_dns_interface = "br-lan";
          FTLCONF_dns_upstreams = "127.0.0.1#5335";
          FTLCONF_dns_domain_name = "lan";
          FTLCONF_dns_listeningMode = "ALL";
          FTLCONF_dhcp_logging = "true";

          FTLCONF_dhcp_active = "true";
          FTLCONF_dhcp_start = "192.168.1.50";
          FTLCONF_dhcp_end = "192.168.1.254";
          FTLCONF_dhcp_router = "192.168.1.1";
          FTLCONF_dhcp_leaseTime = "24";
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
