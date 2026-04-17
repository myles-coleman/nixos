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
    package = pkgs.unstable.tailscale;
    useRoutingFeatures = "both";
    openFirewall = true;
  };

  # Docker
  virtualisation.docker.enable = true;

  # Declarative OCI containers
  #
  # Networking: all containers join a shared "homelab-net" Docker network
  # (created manually with `docker network create homelab-net`).
  # This is required because containers on Docker's default bridge network
  # cannot reach host-published ports (e.g. 10.0.0.150:8222 times out from
  # inside a container). With a shared network, NPM can proxy to other
  # containers by name (e.g. "jellyfin", "vaultwarden") on their internal
  # ports, bypassing host port mappings entirely.
  #
  # Volume mounts: each container's data predates this NixOS config.
  # The host paths reflect the original docker-compose directory structure:
  #   ~/jellyfin/config/  (not ~/jellyfin/ — config is one level deeper)
  #   ~/vaultwarden/data/ (data lives directly here)
  #   ~/nginx/data/       (not ~/nginx/ — NPM's /data expects database.sqlite here)
  #   ~/nginx/letsencrypt (SSL certs at the top level of ~/nginx/)
  #
  # NPM proxy host destinations (configured in NPM UI at :81):
  #   jellyfin.cowlab.org    -> http://jellyfin:8096     (container name on homelab-net)
  #   vaultwarden.cowlab.org -> http://vaultwarden:80    (container name on homelab-net)
  #   npm.cowlab.org         -> http://127.0.0.1:81      (self-proxy via loopback)
  #   Other hosts (pihole, pikvm, chat) use their LAN IPs since they're on other machines.
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      jellyfin = {
        image = "jellyfin/jellyfin:latest";
        ports = [
          "8096:8096/tcp"
          "7359:7359/udp" # auto-discovery
        ];
        volumes = [
          "/home/${mainUser}/jellyfin/config:/config"
          "/home/${mainUser}/jellyfin/config/cache:/cache"
          "/mnt/md0/data/media:/data" # RAID10 media library
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--device=/dev/dri:/dev/dri" # Intel Arc A310 HW transcoding
          "--network=homelab-net"
        ];
      };

      vaultwarden = {
        image = "vaultwarden/server:latest";
        ports = [
          "8222:80/tcp" # host 8222 -> container 80 (avoids conflict with NPM on port 80)
        ];
        volumes = [
          "/home/${mainUser}/vaultwarden/data:/data"
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--network=homelab-net"
        ];
      };

      nginx-proxy-manager = {
        image = "jc21/nginx-proxy-manager:latest";
        ports = [
          "80:80/tcp" # HTTP
          "443:443/tcp" # HTTPS
          "81:81/tcp" # Admin UI
        ];
        volumes = [
          "/home/${mainUser}/nginx/data:/data"
          "/home/${mainUser}/nginx/letsencrypt:/etc/letsencrypt"
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--network=homelab-net" # shared network so NPM can reach other containers by name
          "--add-host=host.docker.internal:host-gateway" # resolve host IP for non-containerized services
        ];
      };
    };
  };

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
    alejandra #for formatting in rebuild script

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

  # Firewall (Samba ports opened by its module via openFirewall;
  # Docker bypasses iptables and manages its own port forwarding)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [2049 111];
  networking.firewall.allowedUDPPorts = [2049 111];

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

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "bee"];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.05";
}
