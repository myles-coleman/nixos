{
  config,
  pkgs,
  lib,
  ...
}: let
  # Kiosk target URL, preserved from the source `rpi3-nixos` configuration.
  kioskUrl = "https://google.com";
  kioskCommand = "${pkgs.cage}/bin/cage -s -- ${pkgs.chromium}/bin/chromium --kiosk --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/tmp/chromium-cache ${kioskUrl}";
in {
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = kioskCommand;
        user = "bee";
      };
      default_session = {
        command = kioskCommand;
        user = "bee";
      };
    };
  };
}
