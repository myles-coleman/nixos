{
  config,
  pkgs,
  lib,
  ...
}: {
  # tmux config
  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      tmuxPlugins.sensible
    ];
  };

  # Ensure opencode npm dependencies are installed
  systemd.user.services.opencode-setup = {
    description = "Install opencode npm dependencies";
    wantedBy = ["default.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p $HOME/.cache/opencode && echo '\"'\"'{\"dependencies\":{\"@ai-sdk/openai-compatible\":\"1.0.31\",\"@opencode-ai/plugin\":\"latest\"}}'\"'\"' > $HOME/.cache/opencode/package.json && cd $HOME/.cache/opencode && ${pkgs.nodejs}/bin/npm install'";
    };
  };

  # Android emulator via Waydroid (LXC container)
  # https://wiki.nixos.org/wiki/Waydroid
  virtualisation.waydroid.enable = true;
}
