{
  config,
  inputs,
  ...
}: let
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  # k3s control plane (NVMe + disko, 16K page size). Host aspect: listing an
  # aspect enables it. Vendor board/kernel modules and host-local files stay
  # plain imports (spec 16).
  flake.modules.nixos.node0 = {config, ...}: {
    imports =
      [
        inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
        inputs.disko.nixosModules.disko
        ../../modules/rpi/disko-config.nix
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
      ]
      ++ (with aspects; [
        k3s-common
        k3s-token-sops
        node-health
        k3s-server
      ])
      ++ (with aspects; [
        rpi-base
      ]);

    networking.hostName = "node0";
    networking.interfaces.end0.ipv4.addresses = [
      {
        address = "10.0.0.140";
        prefixLength = 24;
      }
    ];
    networking.defaultGateway = "10.0.0.1";
    networking.nameservers = ["1.1.1.1"];
  };
}
