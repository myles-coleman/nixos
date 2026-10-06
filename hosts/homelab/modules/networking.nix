{
  config,
  pkgs,
  lib,
  ...
}: {
  # Static IP on ethernet (NetworkManager itself is enabled by the
  # `networkmanager` aspect).
  networking.interfaces.eno1 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "10.0.0.150";
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];

  # Firewall (Samba ports opened by its module via openFirewall;
  # Docker bypasses iptables and manages its own port forwarding)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [2049 111];
  networking.firewall.allowedUDPPorts = [2049 111];
}
