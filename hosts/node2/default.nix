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
  };
}
