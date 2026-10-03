{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.cli-core.enable = lib.mkEnableOption "core CLI tooling (vim, htop, tree, alejandra, gh)";

  config = lib.mkIf config.my.roles.cli-core.enable {
    environment.systemPackages = with pkgs; [
      vim
      htop
      tree
      alejandra
      gh
    ];
  };
}
