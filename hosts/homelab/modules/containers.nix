{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  # Docker
  virtualisation.docker.enable = true;

  # Declarative OCI containers
  #
  # Networking: all containers join a shared "homelab-net" Docker network
  # (created manually with `docker network create homelab-net`).
  # This is required because containers on Docker's default bridge network
  # cannot reach host-published ports (e.g. 10.0.0.150:8222 times out from
  # inside a container). With a shared network, NPM can proxy to other
  # containers by name (e.g. "jellyfin", "vaultwarden") on their internal
  # ports, bypassing host port mappings entirely.
  #
  # Volume mounts: each container's data predates this NixOS config.
  # The host paths reflect the original docker-compose directory structure:
  #   ~/jellyfin/config/  (not ~/jellyfin/ — config is one level deeper)
  #   ~/vaultwarden/data/ (data lives directly here)
  #   ~/nginx/data/       (not ~/nginx/ — NPM's /data expects database.sqlite here)
  #   ~/nginx/letsencrypt (SSL certs at the top level of ~/nginx/)
  #
  # NPM proxy host destinations (configured in NPM UI at :81):
  #   jellyfin.cowlab.org    -> http://jellyfin:8096     (container name on homelab-net)
  #   vaultwarden.cowlab.org -> http://vaultwarden:80    (container name on homelab-net)
  #   npm.cowlab.org         -> http://127.0.0.1:81      (self-proxy via loopback)
  #   Other hosts (pihole, pikvm, chat) use their LAN IPs since they're on other machines.
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      jellyfin = {
        image = "jellyfin/jellyfin:latest";
        ports = [
          "8096:8096/tcp"
          "7359:7359/udp" # auto-discovery
        ];
        volumes = [
          "/home/${mainUser}/jellyfin/config:/config"
          "/home/${mainUser}/jellyfin/config/cache:/cache"
          "/mnt/md0/data/media:/data" # RAID10 media library
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--device=/dev/dri:/dev/dri" # Intel Arc A310 HW transcoding
          "--network=homelab-net"
        ];
      };

      vaultwarden = {
        image = "vaultwarden/server:latest";
        ports = [
          "8222:80/tcp" # host 8222 -> container 80 (avoids conflict with NPM on port 80)
        ];
        volumes = [
          "/home/${mainUser}/vaultwarden/data:/data"
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--network=homelab-net"
        ];
      };

      nginx-proxy-manager = {
        image = "jc21/nginx-proxy-manager:latest";
        ports = [
          "80:80/tcp" # HTTP
          "443:443/tcp" # HTTPS
          "81:81/tcp" # Admin UI
        ];
        volumes = [
          "/home/${mainUser}/nginx/data:/data"
          "/home/${mainUser}/nginx/letsencrypt:/etc/letsencrypt"
        ];
        environment = {
          TZ = "America/Los_Angeles";
        };
        extraOptions = [
          "--network=homelab-net" # shared network so NPM can reach other containers by name
          "--add-host=host.docker.internal:host-gateway" # resolve host IP for non-containerized services
        ];
      };
    };
  };
}
