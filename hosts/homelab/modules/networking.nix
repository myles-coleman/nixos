{
  config,
  pkgs,
  lib,
  ...
}: let
  # ── sandbox guest egress filter (spec 21, Unit 3) ────────────────────────────
  #
  # `k3s-common` sets `networking.firewall.enable = false` on the cluster nodes and
  # NixOS `networking.firewall` only filters *inbound* anyway, so the guest cannot
  # be trusted to limit its own egress: a guest-root attacker would simply turn it
  # off. The filter therefore lives here, on the hypervisor, where it survives guest
  # root.
  #
  # It is loaded by a oneshot rather than through `networking.nftables.enable`,
  # because switching the firewall backend would also take over the Docker and
  # bridge rules this host already depends on.
  #
  # The guest is matched two ways: the QEMU tap it enters through, and its fixed
  # MAC. `qemu-bridge-helper` allocates the first free `tapN`, so the name is not
  # guaranteed, and the MAC alone is not enough because guest root can change it.
  # Either match is sufficient to apply the policy.
  sandboxEgressRules = pkgs.writeText "sandbox-egress.nft" ''
    table inet sandbox_egress {
      chain forward {
        type filter hook forward priority -150; policy accept;

        iifname "tap0" jump sandbox_node
        ether saddr 02:00:00:00:5a:01 jump sandbox_node
      }

      # Traffic from the guest to the hypervisor's *own* address is locally
      # delivered and never reaches the forward hook, so a forward-only filter
      # leaves the guest able to reach homelab's sshd, NFS and Samba. This chain
      # closes that hole; nothing on the guest legitimately needs to reach the
      # host itself.
      chain input {
        type filter hook input priority -150; policy accept;

        iifname "tap0" jump sandbox_node_local
        ether saddr 02:00:00:00:5a:01 jump sandbox_node_local
      }

      chain sandbox_node_local {
        ct state established,related accept
        drop
      }

      chain sandbox_node {
        ct state established,related accept

        # The k3s API (kube-vip VIP) and flannel VXLAN to the cluster nodes.
        ip daddr 10.0.0.200 tcp dport 6443 accept
        ip daddr { 10.0.0.140, 10.0.0.141, 10.0.0.142, 10.0.0.143, 10.0.0.144 } udp dport 8472 accept

        # The guest's own resolvers.
        ip daddr { 1.1.1.1, 8.8.8.8 } udp dport 53 accept
        ip daddr { 1.1.1.1, 8.8.8.8 } tcp dport 53 accept

        # Everything else to the LAN is denied: SMB, NFS, the kubelets, the API on
        # any other node, the Docker-published services. Pods (10.42.0.0/16) and
        # services (10.43.0.0/16) sit outside these ranges and stay reachable, so
        # cluster traffic and the squid hop are unaffected.
        ip daddr { 10.0.0.0/24, 192.168.1.0/24 } drop

        # Tailscale: control/DERP, STUN, and the direct endpoint.
        tcp dport 443 accept
        udp dport { 3478, 41641 } accept

        return
      }
    }
  '';
in {
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
      # A flat LAN: one uplink plus VM taps, no loops. STP's default forward delay
      # keeps the port in `listening` for ~30s after a bridge comes up, during which
      # the host has no LAN at all. Disable it so the port forwards immediately.
      bridge = {
        stp = "false";
        forward-delay = "0";
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

  # Loader for the sandbox guest egress filter above. Deletes the table first so a
  # rebuild converges instead of stacking duplicate rules, and stays ordered after
  # Docker so the table exists alongside the bridge setup it depends on.
  systemd.services.sandbox-node-egress-filter = {
    description = "Load the sandbox guest egress filter (spec 21)";
    wants = ["docker.service"];
    after = ["docker.service" "network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.nftables}/bin/nft delete table inet sandbox_egress 2>/dev/null || true
      ${pkgs.nftables}/bin/nft -f ${sandboxEgressRules}
    '';
  };
}
