{
  flake.modules.nixos.cli-extras = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      wget
      fastfetch
      gnumake
      ranger
    ];
  };
}
