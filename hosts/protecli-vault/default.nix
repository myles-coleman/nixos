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
  ];

  # UEFI boot with systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "protecli";

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
  virtualisation.docker.enable = true;

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
