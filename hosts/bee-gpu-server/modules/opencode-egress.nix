# Host-enforced egress containment for the OpenCode sandbox instances
# (Spec 18). Provides the allowlisting squid forward proxy and the per-instance
# nftables rules plus the tailnet DNAT. The instance roster is read from the
# internal `opencodeSandbox.instances` option defined in ./opencode-agents.nix.
{
  config,
  pkgs,
  lib,
  ...
}: let
  instances = config.opencodeSandbox.instances;

  modelPort = 8080;
  # Docker's default bridge subnet: the model is a Docker-published port, so an
  # instance's request to the host-side address is DNAT-rewritten into this
  # subnet before the filter hook and becomes forwarded traffic.
  dockerSubnet = "172.17.0.0/16";

  allowDomains = [
    "github.com"
    "api.github.com"
    "codeload.github.com"
    "cache.nixos.org"
    "channels.nixos.org"
    "registry.npmjs.org"
    # Opt-in OpenCode Go provider endpoint (Spec 19).
    "opencode.ai"
  ];
  domainList = lib.concatStringsSep " " allowDomains;

  # Squid 7 wants a certificate on an `ssl-bump` port even when it only peeks
  # and splices (never MITMs); this throwaway cert is never presented.
  bumpCert = pkgs.runCommand "opencode-squid-bump-cert" {nativeBuildInputs = [pkgs.openssl];} ''
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout key.pem -out cert.pem -days 3650 -subj "/CN=opencode-egress"
    cat key.pem cert.pem > $out
  '';

  instanceAcls = lib.concatMapStringsSep "\n" (i: "acl inst_${i.name} src ${i.localIp}") instances;
  sourceNegation = lib.concatMapStringsSep " " (i: "!inst_${i.name}") instances;
  listeners =
    lib.concatMapStringsSep "\n" (
      i:
      # `ssl-bump` with a static cert but no `generate-host-certificates`:
      # squid only peeks at the ClientHello for SNI and then splices, so the
      # certificate-generation helper is never spawned.
      "http_port ${i.hostAddress}:${toString i.proxyPort} ssl-bump cert=${bumpCert}"
    )
    instances;
  accessLogs = lib.concatMapStringsSep "\n" (i: "access_log stdio:/var/log/squid/${i.name}.log squid") instances;

  squidConf = ''
    # OpenCode egress allowlisting forward proxy (Spec 18).
    # One listener per instance, source-scoped, HTTPS allowlisted by server name
    # (SNI peek then splice) with no TLS interception.

    acl SSL_ports port 443
    acl CONNECT method CONNECT
    acl step1 at_step SslBump1

    ${instanceAcls}

    acl allowed_domains dstdomain ${domainList}
    acl allowed_sni ssl::server_name ${domainList}

    # Only the configured instance sources may use this proxy at all.
    http_access deny ${sourceNegation}

    # Allow CONNECT only to allowlisted server names, cleartext only to
    # allowlisted domains, and deny everything else.
    http_access allow CONNECT allowed_sni
    http_access allow allowed_domains
    http_access deny all

    # Peek at the ClientHello for SNI, then splice without decrypting.
    ssl_bump peek step1
    ssl_bump splice all

    ${accessLogs}
    cache_log stdio:/var/log/squid/cache.log

    # squid spawns the TLS certificate helper for any ssl-bump port; point it at
    # a writable, pre-initialized database (see squid-ssl-db below).
    sslcrtd_program ${pkgs.squid}/libexec/security_file_certgen -s /var/cache/squid/ssl_db -M 4MB
    sslcrtd_children 5

    ${listeners}

    cache_effective_user squid squid
    pid_filename /run/squid.pid
    coredump_dir /var/cache/squid
  '';
in {
  services.squid = {
    enable = true;
    configText = squidConf;
  };

  # squid's ssl-bump port spawns the certificate helper, which requires an
  # initialized database directory on a writable path. Initialize it before
  # squid starts.
  systemd.services.squid-ssl-db = {
    description = "Initialize the squid TLS certificate database";
    before = ["squid.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install -d -m 0750 -o squid -g squid /var/cache/squid
      if [ ! -d /var/cache/squid/ssl_db ]; then
        ${pkgs.squid}/libexec/security_file_certgen -c -s /var/cache/squid/ssl_db -M 4MB
        chown -R squid:squid /var/cache/squid/ssl_db
      fi
    '';
  };

  # bee-gpu-server uses protecli-vault as a Tailscale exit node with
  # ExitNodeAllowLANAccess=false, so Tailscale's policy table 52 (evaluated
  # before `main`) captures a default route plus 172.17.0.0/16 and
  # 192.168.1.0/24. Host<->container traffic to the local Docker subnet and to
  # each sandbox subnet would therefore be sent into the tunnel instead of the
  # local veth/bridge. Exempt those local container subnets so they resolve via
  # the main table. (This also restores the pre-existing local model endpoint,
  # which was unreachable for the same reason.)
  systemd.services.opencode-route-exceptions = {
    description = "Exempt local container subnets from the Tailscale exit-node table";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      iprule() {
        ${pkgs.iproute2}/bin/ip rule del to "$1" lookup main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip rule add to "$1" lookup main priority 100
      }
      ${lib.concatMapStringsSep "\n" (i: ''iprule 10.201.${toString i.index}.0/30'') instances}
      iprule 172.17.0.0/16
    '';
  };

  # squid binds each instance's host veth address, which is assigned by the
  # container's ExecStartPost. The container unit is Type=notify, so `After=`
  # does not wait for that address; gate squid (and anything else that needs it)
  # on a readiness probe instead.
  systemd.services.opencode-veth-ready = {
    description = "Wait for OpenCode instance veth addresses";
    after = map (i: "container@${i.name}.service") instances;
    requires = map (i: "container@${i.name}.service") instances;
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "opencode-wait-veth" ''
        set -eu
        deadline=$((SECONDS + 60))
        while [ "$SECONDS" -lt "$deadline" ]; do
          ready=1
          ${lib.concatMapStringsSep "\n" (
            i: ''
              if ! ${pkgs.iproute2}/bin/ip -4 -o addr show dev ve-${i.name} 2>/dev/null \
                | grep -qF " ${i.hostAddress}/"; then
                ready=0
              fi
            ''
          )
          instances}
          if [ "$ready" = 1 ]; then
            exit 0
          fi
          sleep 1
        done
        echo "opencode-veth-ready: timed out waiting for instance veth addresses" >&2
        exit 1
      '';
    };
  };

  systemd.services.squid = {
    after = ["opencode-veth-ready.service"] ++ map (i: "container@${i.name}.service") instances;
    wants = ["opencode-veth-ready.service"] ++ map (i: "container@${i.name}.service") instances;
  };

  # nftables is required for the per-instance rules. The host's Docker uses the
  # nft backend (xtables-nft), so blacklisting the legacy ip_tables module is
  # safe and the firewall switches to its nftables backend.
  networking.nftables.enable = true;

  # Instance -> proxy listener is host-local (input path): the firewall's input
  # chain is default-drop, so the proxy port is opened for exactly the instance
  # source. All other instance traffic is not permitted here and is dropped.
  networking.firewall.extraInputRules =
    lib.concatMapStringsSep "\n" (
      i:
        "iifname \"ve-${i.name}\" ip saddr ${i.localIp} ip daddr ${i.hostAddress} "
        + "tcp dport ${toString i.proxyPort} accept comment \"opencode proxy ${i.name}\""
    )
    instances;

  # Forward path: an instance may only *initiate* traffic to the Docker-published
  # model endpoint; every other forwarded packet it initiates is dropped.
  # Established/related replies (the model's responses, and replies to the
  # tailnet DNAT) must pass, so they are accepted first.
  networking.nftables.tables."opencode-egress" = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy accept;

        ${lib.concatMapStringsSep "\n" (
          i: "iifname \"ve-${i.name}\" ct state established,related accept comment \"return traffic ${i.name}\""
        )
        instances}

        ${lib.concatMapStringsSep "\n" (
          i:
            "iifname \"ve-${i.name}\" ip saddr ${i.localIp} ip daddr ${dockerSubnet} "
            + "tcp dport ${toString modelPort} accept comment \"opencode model ${i.name}\""
        )
        instances}

        ${lib.concatMapStringsSep "\n" (
          i: "iifname \"ve-${i.name}\" drop comment \"deny other opencode egress ${i.name}\""
        )
        instances}
      }
    '';
  };

  # Tailnet-only reachability: DNAT the instance port only for traffic that
  # arrives on the Tailscale interface. Nothing is forwarded on LAN/WAN.
  networking.nftables.tables."opencode-egress-nat" = {
    family = "ip";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        ${lib.concatMapStringsSep "\n" (
          i:
            "iifname \"tailscale0\" tcp dport ${toString i.serverPort} "
            + "dnat ip to ${i.localIp}:${toString i.serverPort} comment \"opencode tailnet DNAT ${i.name}\""
        )
        instances}
      }
    '';
  };

  # The DNAT targets the container's veth address, not the tailnet address, so
  # net.ipv4.ip_nonlocal_bind is not required (Spec 18 task 4.5).
}
