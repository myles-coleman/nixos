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
        ];
      };
    };
  };
}
