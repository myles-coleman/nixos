# Guest-side configuration for the dedicated amd64 k3s node that runs the
# Kubernetes Agent Sandbox (spec 20, Unit 2).
#
# This module is the *guest's* NixOS config. It is imported by
# `hosts/homelab/default.nix` under `microvm.vms.sandbox-node.config.imports`
# alongside the shared aspects, so it is evaluated as part of homelab's closure
# (`nix flake check` type-checks it) and shares the host's /nix/store.
#
# It is a plain module (no flake refs): the aspect list and the `microvm.vms`
# wrapper live in the host's `default.nix`, which closes over the flake config.
{
  config,
  pkgs,
  lib,
  ...
}: let
  # The guest's fixed MAC. Both the bridge interface and the `end0` rename match
  # on it, so the NIC name is stable across boots and the shared flat aspects
  # (which expect `end0`) work unchanged.
  macAddress = "02:00:00:00:5a:01";

  # Persistent state that a tmpfs root would otherwise silently lose. Only
  # `/etc/rancher/node` is persisted under `/etc/rancher`, so NixOS-managed
  # content such as `/etc/rancher/k3s/registries.yaml` is regenerated each boot
  # rather than shadowed. `/etc/machine-id` is NOT a volume — it is initialised
  # deterministically from `microvm.machineId`.
  volumeDir = "/var/lib/microvms/sandbox-node/volumes";

  # The guest's own ciphertext. Provisioned by sub-task 2.6 (the guest's age key
  # must be generated on the host and added to `.sops.yaml` first).
  sopsFile = ../../../secrets/hosts/sandbox-node.yaml;

  # The cluster nodes that must reach this guest's kubelet and VXLAN endpoint.
  clusterNodes = ["10.0.0.140" "10.0.0.141" "10.0.0.142" "10.0.0.143" "10.0.0.144"];

  # Build one iptables rule per node, because the firewall's extra commands take
  # iptables syntax and cannot express a source set without an ipset.
  perNodeRule = rule: lib.concatMapStringsSep "\n" (ip: "iptables -w -A nixos-fw -s ${ip} ${rule} -j nixos-fw-accept") clusterNodes;

  # Containerd 2.x runtime config template. `{{ template "base" . }}` extends the
  # k3s base template; the `gvisor` handler is a new table, so appending it does
  # not create a duplicate table. `runtime_type` is `io.containerd.runsc.v1` with
  # no `BinaryName` (the shim is found on the service PATH).
  containerdTemplate = pkgs.writeText "k3s-containerd-config-v3.toml.tmpl" ''
    {{ template "base" . }}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.gvisor]
      runtime_type = "io.containerd.runsc.v1"
  '';
in {
  config = lib.mkMerge [
    {
      # ── microvm shape ───────────────────────────────────────────────────────
      microvm = {
        # Deterministic identity; also initialises /etc/machine-id.
        machineId = "5a0d0000-0000-4000-8000-000000000001";

        # Explicit sizing (spec 20, Unit 2). microvm.nix defaults to 512 MiB / 1
        # vCPU, which cannot hold a k3s agent *plus* the sandbox pod (the pod was
        # Unschedulable: "Insufficient memory"). homelab has 16 cores and ~15 GiB
        # and also runs Jellyfin and the RAID, so the guest takes a fixed slice.
        mem = 6144;
        vcpu = 4;

        # Attach to homelab's `br0` through QEMU's bridge helper. The guest lands
        # on the cluster's broadcast domain — required for flannel VXLAN, kubelet
        # and MetalLB's L2 ARP — and host<->guest traffic keeps working.
        interfaces = [
          {
            type = "bridge";
            id = "vm-sandbox";
            bridge = "br0";
            mac = macAddress;
          }
        ];

        # Share the host's store instead of building a huge image.
        shares = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
        ];

        volumes = [
          # containerd images + k3s local-path PV data
          {
            image = "${volumeDir}/var-lib-rancher.img";
            mountPoint = "/var/lib/rancher";
            size = 40960;
          }
          {
            image = "${volumeDir}/var-lib-kubelet.img";
            mountPoint = "/var/lib/kubelet";
            size = 5120;
          }
          # keeps the node's tailnet identity instead of consuming a fresh auth key each boot
          {
            image = "${volumeDir}/var-lib-tailscale.img";
            mountPoint = "/var/lib/tailscale";
            size = 256;
          }
          # the SSH host key (spec 21, Unit 3) — a stable identity for an otherwise
          # disposable guest, so operator tooling stops tripping over a changed key
          # every boot
          {
            image = "${volumeDir}/var-lib-ssh.img";
            mountPoint = "/var/lib/ssh";
            size = 64;
          }
          # the age key
          {
            image = "${volumeDir}/var-lib-sops-nix.img";
            mountPoint = "/var/lib/sops-nix";
            size = 64;
          }
          # the agent node password — losing it means k3s rejects the node with
          # "Node password rejected"
          {
            image = "${volumeDir}/etc-rancher-node.img";
            mountPoint = "/etc/rancher/node";
            size = 64;
          }
          # NOTE: /etc/ssh is deliberately NOT persisted. A volume mounted over it
          # shadows NixOS-managed /etc/ssh/sshd_config (a store symlink), so sshd
          # fails to start ("Failed to start SSH Daemon", port 22 closed) — which
          # also blocks host-key provisioning. The host key itself lives at
          # /var/lib/ssh instead (spec 21, Unit 3), which keeps the identity across
          # boots without shadowing the config directory.
        ];
      };

      # ── identity and networking ─────────────────────────────────────────────
      networking.hostName = "sandbox-node";

      # Rename the guest NIC to `end0` on the fixed MAC so the shared flat aspects
      # work unchanged (they assume `end0`).
      systemd.network.links."10-end0" = {
        matchConfig.MACAddress = macAddress;
        linkConfig.Name = "end0";
      };

      networking.interfaces.end0.ipv4.addresses = [
        {
          address = "10.0.0.146";
          prefixLength = 24;
        }
      ];
      # microvm.nix runs systemd-networkd inside the guest, where a plain string
      # gateway fails the "defaultGateway.interface is not optional" assertion, so
      # the interface is named explicitly.
      networking.defaultGateway = {
        address = "10.0.0.1";
        interface = "end0";
      };
      networking.nameservers = ["1.1.1.1"];

      # The guest uses the `end0` name for k3s/flannel (the aspect's default),
      # stated explicitly so the assumption is visible.
      k3sAgent.interface = "end0";

      # ── node identity in the cluster ────────────────────────────────────────
      # A label + NoSchedule taint mirroring the cluster's `gpu=amd:NoSchedule`
      # convention. The RuntimeClass nodeSelector and the sandbox pod toleration
      # pair with these. Lists merge with the aspect's flags.
      services.k3s.extraFlags = [
        "--node-label=sandbox.node/runtime=gvisor"
        "--node-taint=sandbox=gvisor:NoSchedule"
      ];

      # ── telemetry (issue #74) ──────────────────────────────────────────────
      # Deliberately no node_exporter or OTel agent in this file. The cluster's
      # `node-exporter` DaemonSet and `signoz-k8s-infra` agent tolerate the
      # `sandbox=gvisor:NoSchedule` taint above and run on this guest, so the
      # guest OS is observed without a second, NixOS-managed exporter to keep in
      # sync. The taint is what keeps every other workload off the node.
      #
      # The Strata collector (`manifests/cluster/sandbox-telemetry` in the
      # homelab-cluster repo) is pinned to this node for the same reason it is
      # hostNetwork: this is the only cluster node that can reach
      # bee-gpu-server's tailnet-only Strata port. Do not "fix" that by opening
      # Strata to the pod network.
      #
      # The runsc logs persisted under /var/lib/runsc-logs below are the
      # intended source for sampled gVisor telemetry. They are not ingested yet;
      # retrieving them is an operator step until a filelog DaemonSet lands.

      # ── inbound firewall (spec 21, Unit 3) ─────────────────────────────────
      # `k3s-common` disables the firewall for every cluster node. This guest
      # re-enables it because it is the untrusted one: an escape from the sandbox
      # pod lands on a host that should not be a general-purpose target.
      #
      # NixOS firewalls filter inbound only, so this does not control egress — that
      # is the hypervisor's job (see hosts/homelab/modules/networking.nix).
      #
      # `networking.firewall.extraInputRules` is declared by the *nftables* backend
      # only (nixos/modules/services/networking/firewall-nftables.nix). On the
      # iptables backend it is accepted but silently ignored, which is why these
      # rules use `extraCommands`: that option is inserted into the firewall script
      # immediately before its final reject.
      networking.firewall = {
        enable = lib.mkForce true;
        extraCommands = ''
          # kubelet and flannel, from cluster nodes only
          ${perNodeRule "-p tcp --dport 10250"}
          ${perNodeRule "-p udp --dport 8472"}

          # operator SSH: the tailnet, and homelab itself for provisioning
          iptables -w -A nixos-fw -p tcp --dport 22 -s 100.64.0.0/10 -j nixos-fw-accept
          iptables -w -A nixos-fw -p tcp --dport 22 -s 10.0.0.150 -j nixos-fw-accept

          # pod and service traffic, including cross-node pod-to-pod over br0 and
          # metrics-server scraping the kubelet from another node
          iptables -w -A nixos-fw -s 10.42.0.0/16 -j nixos-fw-accept
          iptables -w -A nixos-fw -s 10.43.0.0/16 -j nixos-fw-accept
        '';
      };

      # `access` enables sshd; the NixOS module then opens 22 to any source. Turn
      # that off so the scoped rules above are the only way in.
      services.openssh.openFirewall = lib.mkForce false;

      # ── operator access ─────────────────────────────────────────────────────
      # `access` provides sshd + the bee user; password auth is off because this is
      # the untrusted node, so key-only SSH is the only way in.
      # `access` sets PasswordAuthentication = true at normal priority; force it off
      # here because this is the untrusted node, so key-only SSH is the way in.
      services.openssh.settings.PasswordAuthentication = lib.mkForce false;
      # A persistent host key on the /var/lib/ssh volume added above. NixOS generates
      # a missing key at the configured path on boot, so no extra unit is needed, and
      # the operator stops seeing a changed-key warning after every guest restart.
      services.openssh.hostKeys = [
        {
          type = "ed25519";
          path = "/var/lib/ssh/ssh_host_ed25519_key";
        }
      ];
      users.users.bee.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
      ];

      system.stateVersion = "25.05";

      # ── gVisor runtime handler (spec 20, Unit 3) ────────────────────────────
      # Installed as a containerd runtime handler. nixpkgs' k3s module only writes
      # the containerd 2.x v2 path, so the v3 template is placed declaratively by
      # tmpfiles instead — and being under the persistent /var/lib/rancher volume
      # it is faithfully re-created on every boot.
      systemd.tmpfiles.rules = [
        "d /var/lib/rancher/k3s/agent/etc/containerd 0755 root root -"
        "C /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl 0644 root root - ${containerdTemplate}"
      ];

      # NixOS systemd services do not inherit /run/current-system/sw/bin, so the
      # `containerd-shim-runsc-v1` binary would not otherwise be found.
      systemd.services.k3s.path = [pkgs.gvisor];

      # ── operator access: tailnet-only, never a NodePort/IngressRoute ─────────      # `tailscale serve` on this (pinned) node proxies the tailnet to the sandbox
      # ClusterIP. A NodePort would listen on every node's LAN IP and have its
      # source rewritten to the node — which most NetworkPolicy implementations
      # always allow — and an IngressRoute would publish an agent code-execution
      # endpoint LAN-wide via Traefik's wildcard DNS + Cloudflare tunnel.
      #
      # The Service has a pinned ClusterIP because the guest's resolver is not
      # cluster DNS, so a Service *name* would not resolve here.
      systemd.services.tailscale-serve-sandbox = {
        description = "Expose the OpenCode sandbox on the tailnet (operator only)";
        wantedBy = ["multi-user.target"];
        wants = ["tailscaled.service" "network-online.target"];
        after = ["tailscaled.service" "network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # `after = tailscaled.service` only orders the start. tailscaled can still
          # be at `NoState` when `tailscale serve` runs, which then fails with
          # "unexpected state: NoState" — and a oneshot cannot `Restart=`, so the
          # unit stays failed for the whole boot. Wait for the backend to actually
          # report Running (up to 2 minutes).
          ExecStartPre = pkgs.writeShellScript "wait-tailscaled-running" ''
            for _ in $(seq 1 60); do
              if ${config.services.tailscale.package}/bin/tailscale status >/dev/null 2>&1; then
                exit 0
              fi
              sleep 2
            done
            echo "tailscaled did not reach Running within 120s" >&2
            exit 1
          '';
          ExecStart = "${config.services.tailscale.package}/bin/tailscale serve --bg --https=443 http://10.43.0.251:4096";
          ExecStop = "${config.services.tailscale.package}/bin/tailscale serve --https=443 off";
        };
      };
    }

    # ── secrets ───────────────────────────────────────────────────────────────
    # A dedicated ciphertext that contains the guest's OWN Tailscale auth key and
    # a scoped k3s agent token — never the server token and never the shared
    # Tailscale key (spec 20, Unit 2). The guest deliberately does NOT list
    # `k3s-token-sops`.
    #
    # Provisioned by sub-task 2.6: the guest's age key must be generated on the
    # host and added to `.sops.yaml` first. Until the ciphertext is committed the
    # guard below leaves the guest without secrets so the flake still evaluates;
    # committing `secrets/hosts/sandbox-node.yaml` activates the block.
    (lib.mkIf (builtins.pathExists sopsFile) {
      sops.defaultSopsFile = sopsFile;

      # Install secrets from a SERVICE, not the stage-2 activation script: the age
      # key lives on a volume, and activation runs before volumes mount, so with the
      # default (`false`) the key is absent and k3s blocks forever on
      #   Waiting for file "/run/secrets/k3s_agent_token" to be created
      sops.useSystemdActivation = true;
      sops.secrets.tailscale_auth_key = {
        owner = "root";
        mode = "0400";
        restartUnits = ["tailscaled.service"];
      };
      sops.secrets.k3s_agent_token = {
        owner = "root";
        mode = "0600";
        restartUnits = ["k3s.service"];
      };

      services.tailscale.authKeyFile = config.sops.secrets.tailscale_auth_key.path;
      services.k3s.tokenFile = config.sops.secrets.k3s_agent_token.path;

      # The token must be decrypted before k3s starts.
      systemd.services.k3s.after = ["sops-install-secrets.service"];
      systemd.services.k3s.wants = ["sops-install-secrets.service"];
    })
  ];
}
