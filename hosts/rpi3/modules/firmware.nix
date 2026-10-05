{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernelModules = ["i2c-dev"];

  # ── Declarative firmware config.txt (task 3.2) ──────────────────────
  # Replaces the imperative firmware-config.txt oneshot. The vendor module
  # renders config.txt at image-build time and already defaults:
  #   arm_64bit, enable_uart, avoid_warnings, disable_overscan,
  #   display_auto_detect, and the `vc4-kms-v3d` overlay.
  # The two remaining source options that are not vendor defaults are kept.
  # The old `kernel=u-boot-rpi3.bin` lines are intentionally dropped: the
  # vendor `raspberry-pi-3.base` sets `boot.loader.raspberry-pi.bootloader`
  # and owns kernel selection, so setting `kernel=` by hand would conflict.
  hardware.raspberry-pi.config = {
    all.options.gpu_mem = {
      enable = true;
      value = 128;
    };
    pi3.options.core_freq = {
      enable = true;
      value = 250;
    };
  };

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Keep the SD image uncompressed; preserved from the source config.
  sdImage.compressImage = false;
}
