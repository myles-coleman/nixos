{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  imports = [
    ./hardware-configuration.nix
    ./home
    ./modules/networking.nix
    ./modules/firewall.nix
    ./modules/services.nix
    ./modules/mullvad.nix
    ./modules/watchdog.nix
    ./modules/wifi.nix
    ../../modules/sops.nix
  ];

  # Legacy BIOS boot with GRUB (FW6C with coreboot uses legacy boot)
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  networking.hostName = "protecli-vault";

  # Users
  users.users.${mainUser} = {
    isNormalUser = true;
    description = mainUser;
    extraGroups = ["wheel" "docker"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMAbRhFuBN78VkdBT6v/SAdPYxqqBWqthWqf6mWLQL8I bee@bee-gpd"
      # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Tailscale: exit node + subnet router. The Vault owns forwarding and SNAT
  # (--netfilter-mode=off) so its custom nftables ruleset is the only data path.
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    openFirewall = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale_auth_key.path;
    extraUpFlags = [
      "--netfilter-mode=off"
      "--advertise-exit-node"
      "--advertise-routes=192.168.1.0/24,10.0.0.0/24"
    ];
    # extraUpFlags only apply on a fresh login. extraSetFlags re-applies the
    # same settings on every boot, which is required for an already-authenticated
    # node (otherwise NetfilterMode stays at the default and nothing is advertised).
    extraSetFlags = [
      "--netfilter-mode=off"
      "--advertise-exit-node"
      "--advertise-routes=192.168.1.0/24,10.0.0.0/24"
    ];
  };

  # Tailscale auth key lives in sops; only root needs to read it.
  sops.secrets.tailscale_auth_key = {
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = ["tailscaled.service"];
  };

  # Alert-only watchdog: never fails open, never rolls back a generation.
  services.mullvadWatchdog.enable = true;

  # Docker (for Pi-hole container)
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      dns = ["8.8.8.8" "1.1.1.1"]; # Fallback DNS for pulling images before Pi-hole is running
    };
  };

  programs.zsh.enable = true;

  # Allow passwordless sudo for remote deploys
  security.sudo.extraRules = [
    {
      users = ["${mainUser}"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    htop
    tree
    alejandra
    ethtool
    tcpdump
    dnsutils
    nftables
    iperf3
    wireguard-tools
  ];

  # Swap
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "bee"];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.05";
}
