{
  config,
  pkgs,
  lib,
  ...
}: {
  # RAID10 kernel support
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
      ARRAY /dev/md0 UUID=318cdb9d:d17fa19d:5750ae54:f4e4e0f2
    '';
  };

  # NFS server
  services.nfs.server = {
    enable = true;
    # Narrowed from `10.0.0.0/24` (spec 20, Unit 2) so neither the microvm guest
    # (10.0.0.146) nor a compromised agent can mount the RAID share read-write.
    # The brief said "four Pi node IPs"; the cluster has five nodes and the
    # in-cluster media apps can be scheduled on any of them, so this lists all five
    # (node0-node4) to preserve every current consumer while still excluding the
    # guest. Confirm or reduce to four if node4 has no NFS consumer.
    exports = ''
      /mnt/md0/data 10.0.0.140(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000) 10.0.0.141(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000) 10.0.0.142(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000) 10.0.0.143(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000) 10.0.0.144(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000)
    '';
  };
  services.rpcbind.enable = true;

  # Samba
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "homelab server (Samba, NixOS)";
        "log file" = "/var/log/samba/log.%m";
        "max log size" = "1000";
        logging = "file";
        "server role" = "standalone server";
        "map to guest" = "bad user";
        "log level" = "3";
      };
      media = {
        path = "/mnt/md0";
        browseable = "yes";
        "read only" = "no";
        writable = "yes";
        "guest ok" = "no";
        "valid users" = "shareduser";
        "force user" = "shareduser";
        "force group" = "shareduser";
        "create mask" = "0775";
        "directory mask" = "0775";
        "force create mode" = "0664";
        "force directory mode" = "0775";
      };
    };
  };
  services.samba-wsdd.enable = true;

  # RAID10 mount
  fileSystems."/mnt/md0" = {
    device = "/dev/md0";
    fsType = "ext4";
    options = ["defaults"];
  };

  # Swap
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];
}
