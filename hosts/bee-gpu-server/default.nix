{
  config,
  inputs,
  ...
}: let
  aspects = config.flake.modules.nixos;
in {
  flake.modules.nixos.bee-gpu-server = {
    config,
    pkgs,
    lib,
    ...
  }: let
    mainUser = "bee";
  in {
    imports =
      [
        ./hardware-configuration.nix
        ./modules/desktop.nix
        ./modules/gpu.nix
        ./modules/containers.nix
        ./modules/mullvad.nix
        ../../modules/sops.nix
        ../../modules/steam-remote-play-client.nix
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.default
      ]
      ++ (with aspects; [
        access
        sudo
        tailscale
        networkmanager
        home-zsh
        cli-core
        cli-extras
        server-base
        unstable
      ]);

    # UEFI boot with systemd-boot
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = "bee-gpu-server";

    # GPU server must stay reachable — block suspend/hibernate from any source
    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };

    users.users.${mainUser} = {
      extraGroups = ["networkmanager" "wheel" "docker" "video" "render"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
        # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
      ];
    };

    # Tailscale: host-local scalar; enable/package/openFirewall come from the
    # `tailscale` aspect.
    services.tailscale.useRoutingFeatures = "both";

    # System packages (shared CLI/server tools come from aspects)
    environment.systemPackages = with pkgs; [
      tmux
      brave
      bat
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
    ];

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

    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = ["nix-command" "flakes"];
    nix.settings.trusted-users = ["root" "bee"];

    time.timeZone = "America/Los_Angeles";
    i18n.defaultLocale = "en_US.UTF-8";

    system.stateVersion = "25.05";
  };
}
