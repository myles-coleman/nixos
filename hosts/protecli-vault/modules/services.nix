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
        image = "pihole/pihole@sha256:f7d1be836e3bc608b56d82fc9904f5a831cdfbc0dc9c6d58f94e4c985c70038b";
        extraOptions = ["--network=host"]; # Required for DHCP broadcast traffic on br-lan

        environment = {
          TZ = "America/Los_Angeles";
          DNSMASQ_LISTENING = "bind"; # Bind only to specific interfaces (br-lan), not all
          PIHOLE_INTERFACE = "br-lan"; # Listen on br-lan interface
          PIHOLE_DNS_ = "127.0.0.1#5335"; # Point to Unbound
          DHCP_ACTIVE = "true";
          DHCP_START = "192.168.1.50";
          DHCP_END = "192.168.1.254";
          DHCP_ROUTER = "192.168.1.1";
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
