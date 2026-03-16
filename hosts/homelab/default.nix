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
  ];

  # BIOS/Legacy boot with GRUB
  boot.loader.grub = {
    enable = true;
    device = "/dev/nvme0n1";
  };

  # RAID10 kernel support
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md0 UUID=318cdb9d:d17fa19d:5750ae54:f4e4e0f2
    '';
  };

  networking.hostName = "homelab";

  # Static IP on ethernet
  networking.networkmanager.enable = true;
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

  # Users
  users.users.${mainUser} = {
    isNormalUser = true;
    description = mainUser;
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
  };

  users.users.shareduser = {
    isNormalUser = true;
    description = "Samba shared user";
  };

  users.users.smb = {
    isNormalUser = true;
    description = "SMB user";
  };

  # SSH (password + key auth)
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
    useRoutingFeatures = "both";
    openFirewall = true;
  };

  # Docker
  virtualisation.docker.enable = true;

  # NFS server
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/md0/data 10.0.0.0/24(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000)
    '';
  };
  services.rpcbind.enable = true;

  # Samba
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "homelab server (Samba, NixOS)";
        "log file" = "/var/log/samba/log.%m";
        "max log size" = "1000";
        logging = "file";
        "server role" = "standalone server";
        "map to guest" = "bad user";
        "log level" = "3";
      };
      media = {
        path = "/mnt/md0";
        browseable = "yes";
        "read only" = "no";
        writable = "yes";
        "guest ok" = "no";
        "valid users" = "shareduser";
        "force user" = "shareduser";
        "force group" = "shareduser";
        "create mask" = "0775";
        "directory mask" = "0775";
        "force create mode" = "0664";
        "force directory mode" = "0775";
      };
    };
  };
  services.samba-wsdd.enable = true;

  # Intel Arc A310 GPU
  hardware.graphics.enable = true;

  # Fan control and hardware monitoring
  # hardware.fancontrol.enable = true;
  environment.systemPackages = with pkgs; [
    # Core tools
    vim
    wget
    curl
    git
    htop
    tmux
    tree
    tldr
    neofetch
    gnumake
    gcc
    gnupg

    # Hardware monitoring
    lm_sensors
    ethtool
    smartmontools
    mdadm
    intel-gpu-tools

    # Intel Arc GPU (hardware video acceleration)
    intel-media-driver

    # Docker / Kubernetes / IaC
    docker-compose
    helm
    k9s
    kustomize
    opentofu
    terraform

    # Languages / runtimes
    python3

    # Networking / infra
    # net-tools
    gh
  ];

  # RAID10 mount
  fileSystems."/mnt/md0" = {
    device = "/dev/md0";
    fsType = "ext4";
    options = ["defaults"];
  };

  # Swap
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  # Firewall (SSH, NFS, Samba ports opened automatically by their modules;
  # Docker bypasses iptables and manages its own port forwarding)
  networking.firewall.enable = true;

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "bee"];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.05";
}
