{
  config,
  pkgs,
  lib,
  ...
}: let
  # Fixed MAC so the guest NIC keeps a stable name across boots. The host tap
  # is created by `hosts/homelab/modules/lab0.nix`.
  macAddress = "02:00:00:00:5a:02";

  juiceShop = pkgs.callPackage ../../../pkgs/juice-shop {};
in {
  # ── disposable Juice Shop target (spec 31, Unit 3) ─────────────────────────
  #
  # Self-contained: no host /nix/store share, no vsock, no 9p. `storeOnDisk`
  # defaults to true when `/nix/store` is not a share, so the guest boots from
  # its own store image. The root is tmpfs, so a restart is a reset.
  microvm = {
    machineId = "5a0d0000-0000-4000-8000-000000000002";
    mem = 1536;
    vcpu = 2;

    interfaces = [
      {
        type = "tap";
        id = "tap-lab0-target";
        mac = macAddress;
      }
    ];

    # Explicit: no host store share, no vsock, no 9p.
    shares = [];
    vsock.cid = null;
    volumes = [];
  };

  networking.hostName = "redteam-target";

  # Rename the NIC to `end0` on the fixed MAC.
  systemd.network.links."10-end0" = {
    matchConfig.MACAddress = macAddress;
    linkConfig.Name = "end0";
  };

  # Static lab address, no gateway, no DNS. There is no route off lab0.
  networking.useDHCP = false;
  networking.interfaces.end0.ipv4.addresses = [
    {
      address = "10.99.0.2";
      prefixLength = 24;
    }
  ];
  networking.nameservers = [];
  networking.firewall.enable = false;

  # The app rewrites files under its working tree at startup, so the copy must
  # be writable. `/var/lib/juice-shop` lives on the tmpfs root and dies with the
  # VM, which is exactly the reset semantics.
  users.groups.juice-shop = {};
  users.users.juice-shop = {
    isSystemUser = true;
    group = "juice-shop";
    home = "/var/lib/juice-shop";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/juice-shop 0755 juice-shop juice-shop -"
  ];

  systemd.services.juice-shop-seed = {
    description = "Seed the disposable Juice Shop working tree";
    wantedBy = ["multi-user.target"];
    before = ["juice-shop.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "juice-shop";
      Group = "juice-shop";
    };
    script = ''
      set -eu
      cp -a ${juiceShop}/share/juice-shop/. /var/lib/juice-shop/
      chmod -R u+w /var/lib/juice-shop
    '';
  };

  systemd.services.juice-shop = {
    description = "OWASP Juice Shop (pinned 20.4.0)";
    wantedBy = ["multi-user.target"];
    after = ["juice-shop-seed.service" "network.target"];
    requires = ["juice-shop-seed.service"];
    serviceConfig = {
      Type = "simple";
      User = "juice-shop";
      Group = "juice-shop";
      WorkingDirectory = "/var/lib/juice-shop";
      ExecStart = "${pkgs.nodejs_24}/bin/node build/app.js";
      Restart = "always";
      RestartSec = 2;
      MemoryMax = "1G";
    };
  };

  system.stateVersion = "25.05";
}
