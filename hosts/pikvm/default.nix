{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/pikvm.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # RPi downstream kernel for CSI-2 (TC358743/unicam) compatibility
  boot.kernelPackages = pkgs.linuxPackages_rpi4;
  boot.initrd.includeDefaultModules = false;
  # Override: all-hardware.nix adds Allwinner/Rockchip modules missing from RPi kernel
  boot.initrd.availableKernelModules = lib.mkForce [
    "vc4"
    "pcie-brcmstb"
    "reset-raspberrypi"
    "mmc_block"
    "usbhid"
    "hid_generic"
    "ext4"
  ];

  # Enable USB OTG via device tree overlay (Pi 4 uses dwc2)
  boot.kernelParams = [
    "modules-load=dwc2,libcomposite"
  ];
  # DT overlays (tc358743, dwc2) are applied by the Pi firmware via config.txt
  # See hosts/pikvm/hardware-configuration.nix for sdImage firmware setup
  # Disable NixOS device tree so U-Boot doesn't override firmware's DTB
  hardware.deviceTree.enable = false;

  # ── Networking ──────────────────────────────────────────────────────
  networking = {
    hostName = "pikvm";
    useDHCP = false;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.0.175";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "10.0.0.1";
    nameservers = ["10.0.0.1" "1.1.1.1"];
  };

  # ── PiKVM ───────────────────────────────────────────────────────────
  services.pikvm = {
    enable = true;
    hostname = "pikvm";
    listenPort = 8080; # change to 443 if you add TLS later
    enableJanus = true;
    enableVNC = false;
    enableIPMI = false;
  };

  # ── SSH ─────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # ── Tailscale client ─────────────────────────────────────────────────
  # Exit-node and subnet-router roles were retired: the Vault
  # (protecli-vault) is the single source of truth for tailnet egress.
  # extraSetFlags actively clears the previously-advertised routes from the
  # node's persisted state (removing extraUpFlags alone does not un-advertise
  # an already-authenticated node).
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    useRoutingFeatures = "both";
    openFirewall = true;
    extraSetFlags = [
      "--advertise-exit-node=false"
      "--advertise-routes="
    ];
  };

  # IP forwarding retained (still enabled by useRoutingFeatures); exit-node
  # and subnet-router duties now live on the Vault.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # ── Basic system packages ───────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    v4l-utils
  ];

  # ── Nix settings ───────────────────────────────────────────────────
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" "@wheel"];
    };
  };

  # ── User account ───────────────────────────────────────────────────
  users.users.bee = {
    isNormalUser = true;
    extraGroups = ["wheel" "video" "gpio"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
    ];
  };

  # ── Passwordless sudo for remote rebuilds ──────────────────────────
  security.sudo.wheelNeedsPassword = false;

  # ── Swap ───────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  system.stateVersion = "25.05";
}
