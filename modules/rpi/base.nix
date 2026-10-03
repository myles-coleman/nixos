{nixos-raspberrypi, ...}: {
  # Shared Raspberry Pi 5 base for every k3s cluster node (node0-node4).
  # Ported from the rpi5-nixos repository's `sharedConfig`.
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
  ];

  # The 16K-page-size jemalloc overlay (node0-node3) changes the Rust toolchain
  # closure, so `zram-generator` is rebuilt from source rather than substituted.
  # Its test harness requires working user namespaces (`unshare` + `/proc/self`
  # writes), which the ARM build runner does not provide; the check is a
  # build-time-only concern and does not affect the runtime system.
  nixpkgs.overlays = [
    (final: prev: {
      zram-generator = prev.zram-generator.overrideAttrs (_: {doCheck = false;});
    })
  ];

  users.users.pi = {
    isNormalUser = true;
    description = "pi";
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
      # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # deploy-rs copies the CI-built closure as `pi` over `ssh-ng://`; the target
  # must trust that user or `require-sigs = true` rejects the unsigned paths.
  nix.settings.trusted-users = ["root" "pi"];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # mDNS for .local resolution on the LAN.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  hardware.enableRedistributableFirmware = true;

  # Preserved from the source nodes; do not bump without a migration.
  system.stateVersion = "25.05";
}
