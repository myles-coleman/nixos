{
  config,
  pkgs,
  lib,
  ...
}: {
  # Kernel modules for game controllers
  boot.kernelModules = ["hid_nintendo" "joydev"];

  # Enable joystick support
  hardware.uinput.enable = true;

  # udev rule for Joy-Con hidraw access. The trailing newline preserves the
  # pre-split blank line before the module's own built-in udev rules.
  services.udev.extraRules = "KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", SUBSYSTEMS==\"hid\", DRIVERS==\"nintendo\", MODE=\"0660\", GROUP=\"input\", TAG+=\"uaccess\"\n";

  # Extended bluetooth settings for GPD
  hardware.bluetooth.settings = {
    General = {
      Experimental = true;
      KernelExperimental = true;
    };
    Policy = {
      AutoEnable = true;
    };
  };
  hardware.bluetooth.input = {
    General = {
      ClassicBondedOnly = false;
    };
  };
}
