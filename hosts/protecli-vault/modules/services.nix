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

        # Security hardening
        hide-identity = true;
        hide-version = true;
      };
    };
  };

  # ── Pi-hole Docker Container (DHCP + DNS with ad blocking) ─────────
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      pihole = {
        image = "pihole/pihole:latest";
        extraOptions = ["--network=host"]; # Required for DHCP broadcast traffic on br-lan

        environment = {
          TZ = "America/Los_Angeles";
          DNSMASQ_LISTENING = "local";
          PIHOLE_DNS_ = "127.0.0.1#5335"; # Point to Unbound
          DHCP_ACTIVE = "true";
          DHCP_START = "10.0.0.50";
          DHCP_END = "10.0.0.254";
          DHCP_ROUTER = "10.0.0.1";
          PIHOLE_DOMAIN = "lan";
          DHCP_LEASETIME = "24";
          REV_SERVER = "false";
          WEBPASSWORD = ""; # Empty -- set manually post-deploy for security
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
