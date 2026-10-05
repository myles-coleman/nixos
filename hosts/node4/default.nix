{
  config,
  inputs,
  ...
}: let
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  # k3s agent (SD-card boot; no NVMe/disko, no eGPU). Host aspect (spec 16).
  # The eGPU/GPU-kernel config was removed from the source repo in
  # rpi5-nixos commit f60faa5, so node4 is a plain SD-card agent.
  flake.modules.nixos.node4 = {config, ...}: {
    imports =
      [
        inputs.nixos-raspberrypi.nixosModules.sd-image
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

    networking.hostName = "node4";
    networking.interfaces.end0.ipv4.addresses = [
      {
        address = "10.0.0.144";
        prefixLength = 24;
      }
    ];
    networking.defaultGateway = "10.0.0.1";
    networking.nameservers = ["1.1.1.1"];
  };
}
