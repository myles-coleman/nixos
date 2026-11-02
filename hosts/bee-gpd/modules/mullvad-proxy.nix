{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mullvad-http-proxy;
in {
  options.services.mullvad-http-proxy = {
    enable = lib.mkEnableOption "an HTTP proxy bridging to the local Mullvad SOCKS5 listener";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8118;
      description = "Loopback port the HTTP proxy listens on.";
    };
  };

  # Only useful when the Mullvad client is connected *on this machine*, because
  # the SOCKS5 listener lives at 10.64.0.1 inside its tunnel. This host routes
  # all traffic through the tailnet exit node instead, so the service is off by
  # default: page fetches already leave via Mullvad that way.
  #
  # Enable it to select `egress = "mullvad"` in ~/.config/websearch/config.toml.
  config = lib.mkIf cfg.enable {
    systemd.services.mullvad-http-proxy = {
      description = "HTTP proxy bridging to the Mullvad SOCKS5 proxy";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "mullvad-daemon.service"];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.gost} -L http://127.0.0.1:${toString cfg.port} -F socks5://10.64.0.1:1080";
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
