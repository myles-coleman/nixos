{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.fonts.enable = lib.mkEnableOption "shared font set (noto, nerd-fonts meslo-lg, font-awesome)";

  config = lib.mkIf config.my.roles.fonts.enable {
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.meslo-lg
      font-awesome
    ];
  };
}
