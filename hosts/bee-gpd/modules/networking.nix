{
  config,
  pkgs,
  lib,
  ...
}: {
  # Static IP configuration for connecting to Protecli Vault via ethernet
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false; # Don't wait for networkd interfaces (NetworkManager handles connectivity)
  systemd.network.networks."10-eno1-vault" = {
    matchConfig.Name = "eno1";
    address = ["192.168.1.2/24"];
    networkConfig = {
      ConfigureWithoutCarrier = true; # Works even when cable unplugged
    };
    linkConfig.RequiredForOnline = "no"; # Don't block boot
  };
}
