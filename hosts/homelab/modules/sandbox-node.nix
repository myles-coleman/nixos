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
          {
            image = "${volumeDir}/etc-ssh.img";
            mountPoint = "/etc/ssh";
            size = 64;
          }
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
