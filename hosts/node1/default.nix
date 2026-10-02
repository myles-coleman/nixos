{
  nixos-raspberrypi,
  disko,
  ...
}: {
  # k3s agent (NVMe + disko, 16K page size).
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
    disko.nixosModules.disko
    ../../modules/rpi/disko-config.nix
    ../../modules/rpi/k3s-agent.nix
  ];

  networking.hostName = "node1";
  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "10.0.0.141";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = ["1.1.1.1"];
}
