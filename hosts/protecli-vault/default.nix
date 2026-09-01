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
    # ./modules/wifi.nix
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
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    openFirewall = true;
  };

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
    wget
    curl
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
