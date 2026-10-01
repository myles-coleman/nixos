{nixos-raspberrypi, ...}: {
  # k3s agent (SD-card boot; no NVMe/disko, no eGPU).
  # The eGPU/GPU-kernel config was removed from the source repo in
  # rpi5-nixos commit f60faa5, so node4 is a plain SD-card agent.
  imports = [
    nixos-raspberrypi.nixosModules.sd-image
    ../../modules/rpi/k3s-agent.nix
  ];

  networking.hostName = "node4";
  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "10.0.0.144";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = ["1.1.1.1"];
}
