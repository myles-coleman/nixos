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

  # UEFI boot with systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "bee-gpu-server";
  networking.networkmanager.enable = true;

  # GPU server must stay reachable — block suspend/hibernate from any source
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # Enable Plasma 6 Desktop Environment
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable Wayland support
  environment.variables = {
    NIXOS_OZONE_WL = "1";
    # Always create a virtual display so krdp works headless (no monitor)
    KWIN_DRM_VIRTUAL_OUTPUT = "1";
  };

  # Enable sound with PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  # Fonts
  fonts = {
    enableDefaultPackages = true;
    fontDir.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.meslo-lg
      font-awesome
      liberation_ttf
    ];
    fontconfig = {
      defaultFonts = {
        monospace = ["MesloLGS Nerd Font Mono"];
        sansSerif = ["Noto Sans"];
        serif = ["Noto Serif"];
      };
    };
  };

  # Users
  users.users.${mainUser} = {
    isNormalUser = true;
    description = mainUser;
    extraGroups = ["networkmanager" "wheel" "docker" "video" "render"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
    ];
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

  # Mullvad VPN
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Docker
  virtualisation.docker.enable = true;

  # Declarative Docker containers
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      qwen-177b = {
        image = "ghcr.io/ggml-org/llama.cpp:server-rocm@sha256:b54c5c6adb542a396885b4b07a5159e9ab0c649e007cc9f7f088799043cc9e4f";
        ports = [
          "8080:8080/tcp"
        ];
        volumes = [
          "/home/${mainUser}/models:/models"
        ];
        extraOptions = [
          "--device=/dev/dri/renderD128:/dev/dri/renderD128"
          "--device=/dev/kfd:/dev/kfd"
          "--group-add=video"
          "--group-add=render"
          "--ipc=host"
          "--cap-add=SYS_PTRACE"
          "--security-opt=seccomp=unconfined"
          "--ulimit=memlock=-1"
        ];
        cmd = [
          "--host"
          "0.0.0.0"
          "--port"
          "8080"
          "-m"
          "/models/qwen-177b-atomic/Qwen3.8-Flash-Next-AD-3.84bpw-IQ4_XS-M64-00001-of-00028.gguf"
          "--jinja"
          "--alias"
          "qwen3.8-flash-next"
          "-ngl"
          "99"
          "-ncmoe"
          "32"
          "-fit"
          "off"
          "-fa"
          "on"
          "-c"
          "100000"
          "-ctk"
          "q4_0"
          "-ctv"
          "q4_0"
          "-b"
          "1024"
          "-ub"
          "512"
          "-t"
          "6"
          "-np"
          "1"
          "--temp"
          "1"
          "--top-k"
          "20"
          "--min-p"
          "0"
          "--top-p"
          "0.95"
          "--metrics"
        ];
      };
    };
  };

  # AMD GPU support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # System packages
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
    fastfetch
    gnumake
    gcc
    gnupg
    alejandra
    ranger
    brave
    bat

    # Hardware monitoring
    lm_sensors

    # AMD GPU tools
    amdgpu_top
    radeontop
    lact

    # Development
    gh

    # Languages / runtimes
    python3

    # KDE/Plasma applications
    kdePackages.plasma-browser-integration
    kdePackages.kdeconnect-kde
    kdePackages.kate
    kdePackages.dolphin
    kdePackages.konsole
    kdePackages.gwenview
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.okular
    kdePackages.filelight
    kdePackages.kcalc
    kdePackages.partitionmanager

    # Misc
    remmina

    # VPN
    mullvad-vpn
  ];

  # Enable KDE Connect
  programs.kdeconnect.enable = false;

  # Enable LACT service for AMD GPU control
  systemd.packages = with pkgs; [lact];
  systemd.services.lactd = {
    description = "AMDGPU Control Daemon";
    enable = true;
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
    wantedBy = ["multi-user.target"];
  };

  # Swap
  swapDevices = [
    {
      device = "/swapfile";
      size = 16384;
    }
  ];

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [3389];

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
