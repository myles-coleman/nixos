# Raspberry Pi 4 hardware configuration for PiKVM
# Based on sd-image-aarch64.nix with custom config.txt for CSI-2 + OTG overlays.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  hardware.enableRedistributableFirmware = true;

  sdImage = {
    compressImage = false;

    # Override firmware partition to include TC358743 + DWC2 overlays
    populateFirmwareCommands = lib.mkForce (let
      configTxt = pkgs.writeText "config.txt" ''
        [pi4]
        kernel=u-boot-rpi4.bin
        enable_gic=1
        armstub=armstub8-gic.bin
        disable_overscan=1
        arm_boost=1

        [all]
        arm_64bit=1
        enable_uart=1
        avoid_warnings=1

        # PiKVM: HDMI capture via TC358743 CSI-2 bridge
        dtoverlay=tc358743

        # PiKVM: USB OTG for HID emulation
        dtoverlay=dwc2,dr_mode=peripheral
      '';
    in ''
      (cd ${pkgs.raspberrypifw}/share/raspberrypi/boot && cp bootcode.bin fixup*.dat start*.elf $NIX_BUILD_TOP/firmware/)

      cp ${configTxt} firmware/config.txt

      # Pi 4 U-Boot + armstub
      cp ${pkgs.ubootRaspberryPi4_64bit}/u-boot.bin firmware/u-boot-rpi4.bin
      cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin firmware/armstub8-gic.bin

      # Pi 4 device trees
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb firmware/
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-400.dtb firmware/
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-cm4.dtb firmware/
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-cm4s.dtb firmware/

      # Overlay .dtbo files (applied by Pi firmware via config.txt)
      mkdir -p firmware/overlays
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/tc358743.dtbo firmware/overlays/
      cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/dwc2.dtbo firmware/overlays/
    '');
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}
