{config, ...}: {
  # Desktop network delta. The shared invariants live in the `networkmanager`
  # and `tailscale` aspects; this aspect composes them and adds the
  # desktop-only behavior (systemd-resolved DNS backend, exit-node routing,
  # Mullvad, mDNS, rpcbind).
  flake.modules.nixos.network = {pkgs, ...}: {
    imports = [
      config.flake.modules.nixos.networkmanager
      config.flake.modules.nixos.tailscale
    ];

    networking.networkmanager.dns = "systemd-resolved"; # Use systemd-resolved as DNS backend

    services.tailscale.useRoutingFeatures = "both"; # Allow this machine to use AND be an exit node

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
