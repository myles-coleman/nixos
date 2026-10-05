{
  config,
  pkgs,
  lib,
  ...
}: {
  # Mullvad VPN
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  environment.systemPackages = with pkgs; [
    mullvad-vpn
  ];
}
