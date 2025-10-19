{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    k3s
    kubectl
    coreutils
    open-iscsi
    cryptsetup
    util-linux
    nfs-utils
    vim
    htop
  ];

  boot.kernelModules = [
    "br_netfilter"
    "overlay"
  ];

  boot.kernelParams = [
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

  systemd.services.k3s.after = [ "network-online.target" ];
  systemd.services.k3s.wants = [ "network-online.target" ];
}
