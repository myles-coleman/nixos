{
  config,
  pkgs,
  lib,
  ...
}: {
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.open = true;

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];
}
