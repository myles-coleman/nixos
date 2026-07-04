{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
  xenia-edge = let
    wine = pkgs.wineWowPackages.staging;
    xenia-src = pkgs.stdenv.mkDerivation {
      pname = "xenia-edge-src";
      version = "c0e1129";
      src = pkgs.fetchurl {
        url = "https://github.com/has207/xenia-edge/releases/download/c0e1129/xenia_edge_windows.zip";
        hash = "sha256-lG3FK6hj1SmyfS44RYefHz0NYVn6UaJ1wPBq+KHLIbo=";
      };
      nativeBuildInputs = [pkgs.unzip];
      sourceRoot = ".";
      installPhase = ''
        mkdir -p $out
        cp -r * $out/
      '';
    };
    launcher = pkgs.writeShellScript "xenia-edge-launcher" ''
      XENIA_DIR="$HOME/.local/share/xenia-edge-win"
      # Sync files from nix store to writable directory
      mkdir -p "$XENIA_DIR"
      cp -u ${xenia-src}/*.exe "$XENIA_DIR/" 2>/dev/null || true
      cp -u ${xenia-src}/*.dll "$XENIA_DIR/" 2>/dev/null || true
      cp -un ${xenia-src}/* "$XENIA_DIR/" 2>/dev/null || true
      cd "$XENIA_DIR"
      exec ${wine}/bin/wine "$XENIA_DIR/xenia_edge.exe" "$@"
    '';
  in
    pkgs.stdenv.mkDerivation {
      pname = "xenia-edge";
      version = "c0e1129";
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/bin
        ln -s ${launcher} $out/bin/xenia-edge
      '';
      meta = {
        description = "Xbox 360 Emulator (Edge fork, D3D12 via Wine)";
        homepage = "https://github.com/has207/xenia-edge";
        license = lib.licenses.bsd3;
        platforms = ["x86_64-linux"];
        mainProgram = "xenia-edge";
      };
    };
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
      noto-fonts-emoji
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
    extraGroups = ["networkmanager" "wheel" "docker"];
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

  # Docker
  virtualisation.docker.enable = true;

  # Declarative Docker containers
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      gemma-4-26b = {
        image = "beebecomebigbee/llama-cpp-vulkan:latest";
        ports = [
          "8080:8080/tcp"
        ];
        volumes = [
          "/home/${mainUser}/models:/models"
        ];
        extraOptions = [
          "--device=/dev/dri/renderD128:/dev/dri/renderD128"
          "--device=/dev/dri/card1:/dev/dri/card1"
        ];
        cmd = [
          "--host"
          "0.0.0.0"
          "--port"
          "8080"
          "-m"
          "/models/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
          "-ngl"
          "99"
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
    neofetch
    gnumake
    gcc
    gnupg
    alejandra
    ranger
    brave

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

    # Emulators
    xenia-edge
    remmina
  ];

  # Enable KDE Connect
  programs.kdeconnect.enable = true;

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
