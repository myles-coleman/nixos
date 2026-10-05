{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
  # Flake-level aspect registry (closed over so the NixOS module's own `config`
  # does not shadow it).
  aspects = config.flake.modules.nixos;
in {
  # `homelab` is a host aspect: listing an aspect enables it. Shared concerns
  # are supplied by aspects under `modules/aspects/`; host-local files stay
  # plain imports. `sops` stays path-imported until the RPi migration.
  flake.modules.nixos.homelab = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports =
      [
        ./hardware-configuration.nix
        ./modules/containers.nix
        ./modules/storage.nix
        ./modules/networking.nix
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.default
      ]
      ++ (with aspects; [
        access
        sudo
        tailscale
        networkmanager
        cli-core
        cli-extras
        server-base
        k8s
        home-zsh
        unstable
      ]);

    # BIOS/Legacy boot with GRUB
    boot.loader.grub = {
      enable = true;
      device = "/dev/nvme0n1";
    };

    networking.hostName = "homelab";

    # Users
    users.users.${mainUser} = {
      extraGroups = ["networkmanager" "wheel" "docker"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
        # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
      ];
    };

    users.users.shareduser = {
      isNormalUser = true;
      description = "Samba shared user";
    };

    users.users.smb = {
      isNormalUser = true;
      description = "SMB user";
    };

    # Tailscale auth key is shared material in common.yaml; only root needs it.
    sops.defaultSopsFile = ../../secrets/common.yaml;
    sops.secrets.tailscale_auth_key = {
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = ["tailscaled.service"];
    };

    # Tailscale: host-local remainder. enable/package/openFirewall come from
    # the `tailscale` aspect; `openFirewall` in the aspect replaces the old
    # inline value.
    services.tailscale = {
      useRoutingFeatures = "client"; # Changed from "both" to "client" to avoid routing conflicts
      authKeyFile = config.sops.secrets.tailscale_auth_key.path;
    };

    # Intel Arc A310 GPU
    hardware.graphics.enable = true;

    # Shared CLI/server/k8s packages come from aspects; only host-specific
    # packages are listed here.
    environment.systemPackages = with pkgs; [
      tmux

      # Hardware monitoring
      ethtool
      smartmontools
      mdadm
      intel-gpu-tools

      # Intel Arc GPU (hardware video acceleration)
      intel-media-driver

      # Docker / Kubernetes / IaC
      docker-compose
      helm
      opentofu
      terraform

      # Languages / runtimes
      python3
    ];

    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = ["nix-command" "flakes"];
    nix.settings.trusted-users = ["root" "bee"];

    time.timeZone = "America/Los_Angeles";
    i18n.defaultLocale = "en_US.UTF-8";

    system.stateVersion = "25.05";
  };
}
