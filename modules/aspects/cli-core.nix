{
  flake.modules.nixos.cli-core = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      vim
      htop
      tree
      alejandra
      gh
    ];
  };
}
