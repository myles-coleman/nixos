{
  config,
  pkgs,
  lib,
  ...
}: let
  br0MAC = "02:00:00:00:5a:03";
  labMAC = "02:00:00:00:5a:04";
  broker = pkgs.callPackage ../../../pkgs/redteam-broker {};
in {
  # ── Stage 1 broker (spec 31, Unit 4) ────────────────────────────────────────
  #
  # Two NICs: the main namespace keeps the br0 leg and the control API; the
  # lab0 leg is moved into a dedicated namespace that runs only the client-side
  # proxy. The main namespace never has a route to lab0.
  microvm = {
    machineId = "5a0d0000-0000-4000-8000-000000000003";
    mem = 1024;
    vcpu = 2;

    interfaces = [
      {
        type = "tap";
        id = "tap-br0-broker";
        mac = br0MAC;
      }
      {
        type = "tap";
        id = "tap-lab0-broker";
        mac = labMAC;
      }
    ];

    shares = [];
    vsock.cid = null;
    volumes = [];
  };

  networking.hostName = "redteam-broker";
  networking.useDHCP = false;
  networking.nameservers = ["1.1.1.1"];
  networking.firewall.allowedTCPPorts = [8443];

  systemd.network.links."10-end0" = {
    matchConfig.MACAddress = br0MAC;
    linkConfig.Name = "end0";
  };
  systemd.network.links."10-lab0" = {
    matchConfig.MACAddress = labMAC;
    linkConfig.Name = "lab0";
  };

  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "10.0.0.151";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "end0";
  };

  # Move the lab NIC out of the main namespace. The main namespace keeps only
  # the br0 leg, so OPA, approval verification, and the control API cannot
  # accidentally reach lab0.
  systemd.tmpfiles.rules = [
    "d /run/redteam 0755 root root -"
  ];

  systemd.services.redteam-netns = {
    description = "Create the red-team proxy netns and move the lab NIC";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "systemd-networkd.service"];
    before = ["redteam-proxy.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.iproute2];
    script = ''
      set -eu
      for _ in $(seq 1 30); do
        ip link show lab0 >/dev/null 2>&1 && break
        sleep 1
      done
      ip netns add redteam-proxy 2>/dev/null || true
      if ip link show lab0 >/dev/null 2>&1; then
        ip link set lab0 netns redteam-proxy
      fi
      ip netns exec redteam-proxy ip link set lo up
      ip netns exec redteam-proxy ip link set lab0 up
      ip netns exec redteam-proxy ip addr add 10.99.0.1/24 dev lab0 2>/dev/null || true
    '';
  };

  systemd.services.redteam-proxy = {
    description = "Red-team lab proxy (lab0 netns)";
    wantedBy = ["multi-user.target"];
    after = ["redteam-netns.service"];
    requires = ["redteam-netns.service"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.iproute2}/bin/ip netns exec redteam-proxy ${broker}/bin/broker proxy --socket /run/redteam/proxy.sock";
      Restart = "always";
      RestartSec = 2;
      MemoryMax = "256M";
    };
  };

  environment.etc = {
    "redteam/scope.yaml".source = ../../../config/redteam/scope.yaml;
    "redteam/scope.yaml.sig".source = ../../../config/redteam/scope.yaml.sig;
    "redteam/techniques.json".source = ../../../config/redteam/techniques.json;
    "redteam/techniques.json.sig".source = ../../../config/redteam/techniques.json.sig;
    "redteam/scope.pub".source = ../../../config/redteam/scope.pub;
    "redteam/approval.pub".source = ../../../config/redteam/approval.pub;
    # Public operator CA. The broker uses it to verify client certificates; the
    # CA private key never leaves bee-gpd.
    "redteam/client-ca.crt".source = ../../../config/redteam/client-ca.crt;
  };

  # The broker's server certificate is self-signed and generated on the guest.
  # The operator pins it in ~/.config/redteam/server.crt. The client certificate
  # is signed by the operator CA, whose key stays on bee-gpd.
  systemd.services.redteam-tls = {
    description = "Generate the broker's self-signed TLS certificate";
    wantedBy = ["multi-user.target"];
    before = ["redteam-broker.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "redteam-broker";
    };
    path = [pkgs.openssl];
    script = ''
      set -eu
      mkdir -p /var/lib/redteam-broker/tls
      if [ ! -f /var/lib/redteam-broker/tls/server.crt ]; then
        openssl req -x509 -newkey ed25519 -nodes \
          -keyout /var/lib/redteam-broker/tls/server.key \
          -out /var/lib/redteam-broker/tls/server.crt \
          -days 30 -subj "/CN=redteam-broker" \
          -addext "subjectAltName=IP:10.0.0.151"
      fi
    '';
  };

  systemd.services.redteam-broker = {
    description = "APTS Stage 1 red-team broker";
    wantedBy = ["multi-user.target"];
    after = ["redteam-proxy.service" "redteam-tls.service" "network.target"];
    requires = ["redteam-proxy.service" "redteam-tls.service"];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${broker}/bin/broker serve \
          --scope /etc/redteam/scope.yaml \
          --scope-sig /etc/redteam/scope.yaml.sig \
          --catalog /etc/redteam/techniques.json \
          --catalog-sig /etc/redteam/techniques.json.sig \
          --scope-pub /etc/redteam/scope.pub \
          --approval-pub /etc/redteam/approval.pub \
          --proxy-socket /run/redteam/proxy.sock \
          --addr 10.0.0.151:8443 \
          --state-dir /var/lib/redteam-broker \
          --tls-cert /var/lib/redteam-broker/tls/server.crt \
          --tls-key /var/lib/redteam-broker/tls/server.key \
          --client-ca /etc/redteam/client-ca.crt
      '';
      StateDirectory = "redteam-broker";
      Restart = "always";
      RestartSec = 2;
      MemoryMax = "512M";
    };
  };

  system.stateVersion = "25.05";
}
