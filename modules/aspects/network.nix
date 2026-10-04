{
  flake.modules.nixos.network = {pkgs, ...}: {
    networking.networkmanager = {
      enable = true;
      dns = "systemd-resolved"; # Use systemd-resolved as DNS backend
    };

    services.tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      useRoutingFeatures = "both"; # Allow this machine to use AND be an exit node
      openFirewall = true;
    };

    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    environment.systemPackages = with pkgs; [
      mullvad-vpn
    ];

    # Enable mDNS for .local domain resolution
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
    };

    services.rpcbind.enable = true;
  };
}
