{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── br0 bridge for the microvm guest (spec 20, Unit 2) ──────────────────────
  #
  # homelab's static address and default gateway move off `eno1` onto a Linux
  # bridge `br0`, with `eno1` enslaved and the guest's tap attached through QEMU's
  # `qemu-bridge-helper` (microvm.nix `interface.type = "bridge"`). This puts the
  # guest on the cluster's broadcast domain, which flannel VXLAN, kubelet and
  # MetalLB's L2 ARP all require, and keeps host<->guest traffic working
  # (`macvtap` makes it impossible by design; `passt` NATs and breaks k3s's
  # bidirectional node-to-node traffic).
  #
  # NetworkManager (enabled by the `networkmanager` aspect) keeps managing the
  # interfaces; the guest tap is attached by the bridge helper, so systemd-networkd
  # is not needed here.
  #
  # HAZARD: this is a remote network change on an auto-deployed host and can lock
  # you out. Apply it by hand, with console access (spec 20, sub-task 2.2), never
  # blindly via CI.
  networking.networkmanager.ensureProfiles.profiles = {
    br0 = {
      connection = {
        id = "br0";
        type = "bridge";
        interface-name = "br0";
        autoconnect = "true";
      };
      ipv4 = {
        method = "manual";
        address1 = "10.0.0.150/24,10.0.0.1";
        dns = "1.1.1.1;8.8.8.8;";
      };
      ipv6 = {
        method = "ignore";
      };
    };
    br0-eno1 = {
      connection = {
        id = "br0-eno1";
        type = "ethernet";
        interface-name = "eno1";
        master = "br0";
        slave-type = "bridge";
      };
    };
  };
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];

  # Docker loads `br_netfilter` and sets the iptables FORWARD policy to DROP, which
  # silently blackholes all bridged guest traffic in a way that looks like "the node
  # never joins". Accept br0<->br0 traffic in DOCKER-USER, which Docker evaluates
  # before its own FORWARD rules.
  systemd.services.docker-user-bridge-accept = {
    description = "Accept br0<->br0 traffic in Docker's DOCKER-USER chain";
    after = ["docker.service"];
    wants = ["docker.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iptables}/bin/iptables -C DOCKER-USER -i br0 -o br0 -j ACCEPT 2>/dev/null \
        || ${pkgs.iptables}/bin/iptables -I DOCKER-USER -i br0 -o br0 -j ACCEPT
    '';
  };

  # Firewall (Samba ports opened by its module via openFirewall;
  # Docker bypasses iptables and manages its own port forwarding)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [2049 111];
  networking.firewall.allowedUDPPorts = [2049 111];
}
