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

      # Spec 28, Unit 1. The version a node reports must be the version it runs.
      # These assertions fail the build rather than letting an unpinned nixpkgs
      # package shadow `services.k3s.package` on PATH again. Matching is by name
      # so the check does not force an insecure 1.3x alias derivation. The
      # service package itself is allowed: the k3s module adds it to
      # `environment.systemPackages` on purpose, and that is the one copy we want.
      assertions = [
        {
          assertion = let
            servicePackage = config.services.k3s.package;
            shadowing =
              lib.filter (
                p: (p.pname or "") == "k3s" && p != servicePackage
              )
              config.environment.systemPackages;
          in
            shadowing == [];
          message = ''
            The `k3s-common` aspect must not add the unpinned nixpkgs `k3s` package
            to `environment.systemPackages`. The NixOS k3s module already puts
            `config.services.k3s.package` on PATH, and a second `k3s` entry makes
            `k3s --version` disagree with the service that systemd actually runs
            (spec 28, Unit 1). Remove `k3s` from the package list.
          '';
        }
        {
          assertion =
            !(lib.any (
                p: (p.pname or "") == "kubectl" || lib.hasPrefix "kubectl-" (p.name or "")
              )
              config.environment.systemPackages);
          message = ''
            The `k3s-common` aspect must not add the unpinned nixpkgs `kubectl`
            package to `environment.systemPackages`. `services.k3s.package`
            provides a kubectl that matches the apiserver minor; the nixpkgs one
            is outside the supported +/-1 minor skew (spec 28, Unit 1). Remove
            `kubectl` from the package list.
          '';
        }
      ];

      # K3s supports upgrading one minor at a time, so this is a deliberate
      # 1.35 -> 1.36 step (spec 28). `mkDefault` lets a host override the minor
      # without editing this shared aspect; the sandbox guest uses that to stay
      # one minor behind the control plane while a hop is in flight.
      #
      # Note: 1.33 is end-of-life (2026-06-28) and its nixpkgs attribute carries
      # `meta.knownVulnerabilities`, but it still *evaluates* — `k3s_1_33` is
      # 1.33.13+k3s2 — so `permittedInsecurePackages` could pin it if a hop ever
      # needed to be split from the nixpkgs bump. The earlier comment claiming
      # nixpkgs "refuses to evaluate" it was wrong.
      services.k3s.package = lib.mkDefault pkgs.k3s_1_36;

      # Do NOT add `k3s` or `kubectl` to this list. The NixOS k3s module already
      # puts `config.services.k3s.package` on PATH (it ships both binaries), so
      # an unpinned `pkgs.k3s` / `pkgs.kubectl` entry silently shadows the
      # running minor: before spec 28 every node's `k3s --version` reported 1.35
      # while the service ran 1.33, and the PATH `kubectl` was two minors ahead
      # of the apiserver (outside the supported +/-1 skew). The assertions below
      # keep that regression out.
      environment.systemPackages = with pkgs; [
        coreutils
        openiscsi
        cryptsetup
        util-linux
        nfs-utils
        vim
        htop
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

      # Tailscale is used by these nodes for ROUTES (to reach the model over the
      # tailnet), not for name resolution. Left at its default, accept-dns rewrites
      # /etc/resolv.conf to 100.100.100.100 and external lookups then fail:
      #   Failed to pull image "registry.k8s.io/...": dial tcp:
      #   lookup registry.k8s.io: device or resource busy
      # which breaks every new image pull on the cluster. Keep the nodes' own
      # resolvers.
      services.tailscale.extraUpFlags = ["--accept-dns=false"];

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
