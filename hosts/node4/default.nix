{
  config,
  inputs,
  ...
}: let
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  # k3s agent (NVMe + disko, 4K page size; no eGPU). Host aspect (spec 16).
  # node4 originally booted from an SD card; it now uses the same disko layout
  # as node0-node3 (`/dev/nvme0n1`: 512M vfat ESP at /boot/firmware + ext4 /).
  # It deliberately does NOT carry `raspberry-pi-5.page-size-16k`: the page size
  # is per-node and only affects that node's containers, and the 16K kernel
  # misses every binary cache (see the build-arm guardrail in AGENTS.md).
  flake.modules.nixos.node4 = {config, ...}: {
    imports =
      [
        inputs.disko.nixosModules.disko
        ../../modules/rpi/disko-config.nix
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
      ]
      ++ (with aspects; [
        rpi-base
        k3s-common
        k3s-token-sops
        node-health
        tailscale
        k3s-agent
      ]);

    networking.hostName = "node4";
    networking.interfaces.end0.ipv4.addresses = [
      {
        address = "10.0.0.144";
        prefixLength = 24;
      }
    ];
    networking.defaultGateway = "10.0.0.1";
    networking.nameservers = ["1.1.1.1"];

    # Tailscale (spec 20, Units 2-3): the fleet-wide model path needs a route on
    # every node. The shared auth key lives in secrets/common.yaml, which the k3s
    # nodes are already recipients of.
    sops.secrets.tailscale_auth_key = {
      sopsFile = ../../secrets/common.yaml;
      owner = "root";
      mode = "0400";
      restartUnits = ["tailscaled.service"];
    };
    services.tailscale.authKeyFile = config.sops.secrets.tailscale_auth_key.path;
  };
}
