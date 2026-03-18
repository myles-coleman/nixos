{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    vulkan-tools
    mesa-demos
    steam-run
    protonup-qt
    (retroarch.withCores (cores:
      with cores; [
        mgba
      ]))
  ];
}
