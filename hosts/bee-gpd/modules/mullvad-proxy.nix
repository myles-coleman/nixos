{
  pkgs,
  lib,
  ...
}: {
  # HTTP proxy for agent page reads, bridged to the Mullvad SOCKS5 listener.
  #
  # Mullvad only speaks SOCKS5 (10.64.0.1:1080, reachable solely while the VPN
  # is connected) and urllib/Node cannot reliably use a socks:// proxy URL, so
  # gost converts one to the other on loopback.
  #
  # Scope: only agent-websearch's fetch_page uses this, via `fetch.proxy` in
  # ~/.config/websearch/config.toml. Nothing else on the machine is proxied --
  # in particular model API calls and tailnet endpoints stay direct.
  #
  # Fail-closed: if Mullvad disconnects, 10.64.0.1 stops answering and the
  # proxy refuses connections rather than falling back to direct egress.
  systemd.services.mullvad-http-proxy = {
    description = "HTTP proxy bridging to the Mullvad SOCKS5 proxy";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "mullvad-daemon.service"];
    # The bridge is only useful with a live tunnel; retry until Mullvad is up.
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.gost} -L http://127.0.0.1:8118 -F socks5://10.64.0.1:1080";
      Restart = "always";
      RestartSec = 5;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
