{
  flake.modules.nixos.k3s-common = {
    config,
    pkgs,
    lib,
    options,
    ...
  }: {
    # Shared k3s settings for every cluster node.
    # Ported from the rpi5-nixos repository's `k3s-common.nix` (spec 16).
    #
    # This aspect is FLAT: it does not import `node-health` or any other RPi
    # aspect. Each host lists every leaf aspect it enables so its real surface
    # is visible in its own import list.
    #
    # Because flattening removes the implicit `k3s-server -> k3s-common` edge
    # that the old module had, listing a k3s role without this aspect would
    # silently build a broken node. The `k3sCommon` marker option below is set
    # here; `k3s-server` and `k3s-agent` assert it is present (see those files).
    options.k3sCommon.enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
      description = "Marker set by the k3s-common aspect so role aspects can assert their dependency.";
    };

    config = {
      k3sCommon.enabled = true;

      services.k3s.package = pkgs.k3s_1_33;

      environment.systemPackages = with pkgs; [
        k3s
        coreutils
        openiscsi
        cryptsetup
        util-linux
        nfs-utils
        vim
        htop
        kubectl
        curl
      ];

      boot.kernelModules = [
        "br_netfilter"
        "overlay"
      ];

      # `mkBefore` pins these cgroup params ahead of the vendor board module's
      # `console=` params, reproducing the pre-migration ordering exactly so the
      # host closure stays unchanged (spec 16 closure-preservation gate).
      boot.kernelParams = lib.mkBefore [
        "cgroup_enable=cpuset"
        "cgroup_memory=1"
        "cgroup_enable=memory"
      ];

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        "net.ipv6.conf.all.accept_ra" = 2;
        "net.bridge.bridge-nf-call-iptables" = 1;
        "net.bridge.bridge-nf-call-ip6tables" = 1;
      };

      networking.firewall.enable = false;
      networking.nftables.enable = false;

      services.openiscsi = {
        enable = true;
        name = "iqn.2016-04.com.open-iscsi:${config.networking.hostName}";
      };

      # Longhorn expects `iscsiadm` on the host PATH.
      system.activationScripts.longhorn-iscsiadm = ''
        mkdir -p /usr/bin
        ln -sf ${pkgs.openiscsi}/bin/iscsiadm /usr/bin/iscsiadm
      '';

      systemd.services.k3s.after = ["network-online.target"];
      systemd.services.k3s.wants = ["network-online.target"];
    };
  };
}
