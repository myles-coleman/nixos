{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.networkmanager = {
    enable = true;
    dns = "systemd-resolved"; # Use systemd-resolved as DNS backend
  };

  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = ["~."]; # Claim root DNS zone so Tailscale MagicDNS doesn't hijack all queries
    fallbackDns = ["1.1.1.1" "8.8.8.8"];
    extraConfig = ''
      DNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google
    '';
  };

  services.tailscale = {
    enable = true;
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

  # fileSystems."/home/bee/media" = {
  #   device = "10.0.0.150:/mnt/md0/data/media";
  #   fsType = "nfs4";
  #   options = [
  #     "rw"
  #     "soft"
  #     "timeo=30"
  #     "retrans=3"
  #     "_netdev"
  #     "rsize=1048576"
  #     "wsize=1048576"
  #     "vers=4.2"
  #     "proto=tcp"
  #   ];
  # };

  services.rpcbind.enable = true;
}
