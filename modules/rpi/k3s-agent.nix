{config, ...}: {
  # Worker/agent config (node1-node4). Ported from rpi5-nixos `k3s-agent.nix`.
  imports = [
    ./k3s-common.nix
    ./k3s-token-sops.nix
  ];

  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://10.0.0.200:6443";
    # `tokenFile` is provided by k3s-token-sops.nix (sops-managed).
    extraFlags = [
      "--node-ip=${(builtins.elemAt config.networking.interfaces.end0.ipv4.addresses 0).address}"
      "--node-external-ip=${(builtins.elemAt config.networking.interfaces.end0.ipv4.addresses 0).address}"
      "--flannel-iface=end0"
    ];
  };
}
