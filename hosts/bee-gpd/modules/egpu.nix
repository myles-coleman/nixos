{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable IOMMU
  boot.kernelParams = ["amd_iommu=on" "iommu=pt"];

  # Thunderbolt support
  services.hardware.bolt.enable = true;
  services.udev.packages = with pkgs; [
    bolt
  ];

  # eGPU hotplug: prevent nvidia modules from loading at boot (GPU isn't on
  # the Thunderbolt bus yet, causing "NVRM: No NVIDIA GPU found" and a broken
  # driver state). Instead, load them on-demand when the GPU appears.
  boot.blacklistedKernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];

  # systemd service to load nvidia modules in the correct order after eGPU hotplug
  # systemd.services.nvidia-egpu = {
  #   description = "Load NVIDIA driver stack for eGPU";
  #   after = ["bolt.service"];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     ExecStart = let
  #       script = pkgs.writeShellScript "load-nvidia-egpu" ''
  #         # Load modules in dependency order
  #         ${pkgs.kmod}/bin/modprobe nvidia
  #         ${pkgs.kmod}/bin/modprobe nvidia_modeset
  #         ${pkgs.kmod}/bin/modprobe nvidia_uvm
  #         ${pkgs.kmod}/bin/modprobe nvidia_drm modeset=1 fbdev=1
  #       '';
  #     in "${script}";
  #   };
  # };

  # udev rules for eGPU hotplug. `mkBefore` keeps this rule ahead of the
  # Joy-Con hidraw rule (defined in `input.nix`) in the merged
  # `services.udev.extraRules` string, matching the pre-split ordering.
  services.udev.extraRules = lib.mkBefore "ACTION==\"add\", SUBSYSTEM==\"pci\", ATTR{vendor}==\"0x10de\", ATTR{class}==\"0x030000\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}=\"nvidia-egpu.service\"";
}
