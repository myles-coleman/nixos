{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mullvadWatchdog;

  handshakeMaxAge = 300;
  checkInterval = 60;
in {
  options.services.mullvadWatchdog = {
    enable = lib.mkEnableOption "alert-only watchdog for the Mullvad wg0 handshake";

    notifyCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "curl -fsS -d \"$1\" https://ntfy.sh/my-topic";
      description = ''
        Optional command invoked with the alert message as its first argument.
        Empty (the default) means alerts go to the journal only. The watchdog
        never fails open and never rolls back a generation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.wg0-watchdog = {
      description = "Mullvad wg0 handshake watchdog (alert-only; never fail-open)";
      path = with pkgs; [
        wireguard-tools
        coreutils
        gawk
        util-linux
        iputils
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail

        now=$(date +%s)
        hs=$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | sort -nr | head -1 || true)

        if [ -z "''${hs:-}" ] || [ "$hs" = "0" ]; then
          age=999999
        else
          age=$(( now - hs ))
        fi

        if [ "$age" -gt ${toString handshakeMaxAge} ]; then
          msg="wg0 has had no handshake for ''${age}s (threshold ${toString handshakeMaxAge}s); the hard kill switch remains active and clients stay hard-killed"
          logger -t wg0-watchdog -p daemon.emerg "$msg"
          ${lib.optionalString (cfg.notifyCommand != "") ''
          ${cfg.notifyCommand} "$msg" || true
        ''}
        else
          # A fresh handshake does not prove the relay forwards traffic. On
          # 2026-11-24 ca-van-wg-201 completed handshakes but dropped every
          # packet, so exit-node clients lost internet while this watchdog was
          # silent. Probe egress through the tunnel and alert when it fails.
          endpoint=$(wg show wg0 endpoints 2>/dev/null | awk '{print $2}' | head -1 || true)
          if ! ping -I wg0 -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
            msg="wg0 handshake is fresh but no traffic reaches 1.1.1.1 through ''${endpoint:-the tunnel}; exit-node clients have no internet - check the Mullvad relay"
            logger -t wg0-watchdog -p daemon.emerg "$msg"
            ${lib.optionalString (cfg.notifyCommand != "") ''
          ${cfg.notifyCommand} "$msg" || true
        ''}
          fi
        fi
      '';
    };

    systemd.timers.wg0-watchdog = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString checkInterval}s";
        Unit = "wg0-watchdog.service";
      };
    };
  };
}
