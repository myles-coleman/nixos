{
  config,
  pkgs,
  lib,
  ...
}: let
  piholeConfig = pkgs.writeText "pihole.toml" ''
    [dns]
    interface = "br-lan"
    upstream = ["127.0.0.1#5335"]

    [dhcp]
    enabled = true
    range = ["192.168.1.50", "192.168.1.254"]
    router = "192.168.1.1"
    domain = "lan"
    lease_time = 24
  '';
in {
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
    preStart = ''
      mkdir -p /var/lib/pihole/etc-pihole
      cp ${piholeConfig} /var/lib/pihole/etc-pihole/pihole.toml
      chown 1000:1000 /var/lib/pihole/etc-pihole/pihole.toml
    '';
  };
}
