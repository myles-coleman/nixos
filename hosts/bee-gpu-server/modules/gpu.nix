{
  config,
  pkgs,
  lib,
  ...
}: {
  # AMD GPU support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # AMD GPU tools
  environment.systemPackages = with pkgs; [
    amdgpu_top
    radeontop
    lact
  ];

  # LACT service for AMD GPU control
  systemd.packages = with pkgs; [lact];
  systemd.services.lactd = {
    description = "AMDGPU Control Daemon";
    enable = true;
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
    wantedBy = ["multi-user.target"];
  };
}
