{
  config,
  inputs,
  ...
}: let
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  # k3s agent (NVMe + disko, 16K page size). Host aspect (spec 16).
  flake.modules.nixos.node2 = {config, ...}: {
    imports =
      [
        inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
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

    networking.hostName = "node2";
    networking.interfaces.end0.ipv4.addresses = [
      {
        address = "10.0.0.142";
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
