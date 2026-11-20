{
  flake.modules.nixos.k3s-agent = {
    config,
    lib,
    ...
  }: {
    # Worker/agent config (node1-node4, and the microvm guest). Ported from
    # rpi5-nixos `k3s-agent.nix` (spec 16). FLAT: does not import `k3s-common` or
    # `k3s-token-sops`; the host lists those explicitly. The assertion below guards
    # the co-dependence with `k3s-common`, which was previously enforced by the
    # import edge.
    #
    # `config.k3sCommon` is declared by the `k3s-common` aspect. Using
    # `... or false` makes the assertion evaluate cleanly to `false` (and yield
    # the friendly message) when `k3s-common` is absent, instead of failing with
    # "attribute 'k3sCommon' missing".
    options.k3sAgent.interface = lib.mkOption {
      type = lib.types.str;
      default = "end0";
      description = ''
        Network interface k3s and flannel use on this agent. Defaults to `end0`,
        which is the Pi nodes' name and the microvm guest's renamed NIC; the
        guest sets it explicitly. Parameterizing it retires a hardcoded
        assumption that has already blocked two node joins (spec 20, Unit 2).
      '';
    };

    # Reservations and eviction thresholds exist because the agents had neither:
    # allocatable equalled capacity, so the scheduler treated the whole 4 GiB of a
    # Pi as pod-usable and filled node1 to 96% of its memory requests with 186%
    # committed limits. Under real usage that left nothing for the OS, kubelet and
    # containerd, and kubelet's PLEG stopped responding
    # ("pleg was last seen active 3m24s ago; threshold is 3m0s"), so the node
    # reported NodeStatusUnknown and every endpoint on it was withdrawn.
    options.k3sAgent.kubeReserved = lib.mkOption {
      type = lib.types.str;
      default = "cpu=200m,memory=300Mi";
      description = ''
        Capacity withheld from scheduling for the Kubernetes components (kubelet,
        containerd, CNI). Not a cgroup-enforced reservation — k3s does not set up
        the reserved cgroups — but it removes the capacity from `allocatable` so
        the scheduler stops overfilling the node.
      '';
    };

    options.k3sAgent.systemReserved = lib.mkOption {
      type = lib.types.str;
      default = "cpu=100m,memory=300Mi";
      description = ''
        Capacity withheld from scheduling for the OS and system services (sshd,
        systemd, the journal). Raise it on hosts running extra daemons.
      '';
    };

    options.k3sAgent.evictionHardMemory = lib.mkOption {
      type = lib.types.str;
      default = "300Mi";
      description = ''
        Hard eviction threshold on `memory.available`. The kubelet evicts pods to
        keep this much memory free, which is the behaviour that was missing: the
        node previously thrashed down to 57 MiB available and stalled instead of
        shedding a workload. Must stay below kubeReserved + systemReserved, or
        nothing is ever schedulable.
      '';
    };

    config = {
      assertions = [
        {
          assertion = config.k3sCommon.enabled or false;
          message = ''
            The `k3s-agent` aspect requires the `k3s-common` aspect, but no module
            set `k3sCommon.enabled = true`. Add `k3s-common` to this host's aspect
            list (listed = enabled), or the node will build without the shared k3s
            settings and iscsi/kernel prerequisites.
          '';
        }
      ];

      services.k3s = {
        enable = true;
        role = "agent";
        serverAddr = "https://10.0.0.200:6443";
        # `tokenFile` is provided by k3s-token-sops.nix (sops-managed) — or, for
        # the microvm guest, by its own scoped agent token from a dedicated
        # ciphertext (spec 20).
        extraFlags = [
          "--node-ip=${(builtins.elemAt config.networking.interfaces.${config.k3sAgent.interface}.ipv4.addresses 0).address}"
          "--node-external-ip=${(builtins.elemAt config.networking.interfaces.${config.k3sAgent.interface}.ipv4.addresses 0).address}"
          "--flannel-iface=${config.k3sAgent.interface}"
          # Passed with --kubelet-arg rather than as k3s-specific flags so the
          # kubelet parses them directly and we do not depend on which spellings
          # k3s re-exports in a given release.
          "--kubelet-arg=kube-reserved=${config.k3sAgent.kubeReserved}"
          "--kubelet-arg=system-reserved=${config.k3sAgent.systemReserved}"
          "--kubelet-arg=eviction-hard=memory.available<${config.k3sAgent.evictionHardMemory}"
        ];
      };
    };
  };
}
