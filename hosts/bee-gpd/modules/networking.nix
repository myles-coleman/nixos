{
  config,
  pkgs,
  lib,
  ...
}: {
  # Break-glass link to the protecli-vault's management port (enp6s0).
  # The Vault is headless: a cable from this laptop to enp6s0 plus a
  # 192.168.200.0/24 address is the only way back in after a bad network
  # generation. The profile is management-only: no default route, no DNS, so
  # WiFi/hotspot stays the internet path.
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false; # Don't wait for networkd interfaces (NetworkManager handles connectivity)
  systemd.network.networks."10-eno1-vault-mgmt" = {
    matchConfig.Name = "eno1";
    address = ["192.168.200.2/24"];
    networkConfig = {
      ConfigureWithoutCarrier = true; # Works even when cable unplugged
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
      # No gateway and no DNS on purpose: this link is management only.
      DNS = [];
    };
    linkConfig.RequiredForOnline = "no"; # Don't block boot
  };
}
