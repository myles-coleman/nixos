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
    exports = ''
      /mnt/md0/data 10.0.0.0/24(rw,sync,no_root_squash,all_squash,anonuid=1000,anongid=1000)
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
