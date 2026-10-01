{
  nixos-raspberrypi,
  disko,
  ...
}: {
  # k3s control plane (NVMe + disko, 16K page size).
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
    disko.nixosModules.disko
    ../../modules/rpi/disko-config.nix
    ../../modules/rpi/k3s-server.nix
  ];

  networking.hostName = "node0";
  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "10.0.0.140";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = ["1.1.1.1"];
}
