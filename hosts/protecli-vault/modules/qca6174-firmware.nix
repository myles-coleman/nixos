{
  pkgs,
  lib,
  ...
}: {
  # Qualcomm QCA6174A-5 (ath10k) firmware pin.
  #
  # The card does not initialise with the firmware that current linux-firmware
  # ships for it. BMI completes and the board data loads, then the device dies
  # before the WMI ready event:
  #
  #   firmware ver WLAN.RM.4.4.1-00309- api 6 ...
  #   board_file api 2 bmi_id N/A crc32 d2863f91
  #   wmi unified ready event not received
  #   device has crashed during init -> could not probe fw (-110)
  #
  # That is reproducible across cold boot, reseat, PCI remove/rescan,
  # skip_otp=1, every irq_mode/reset_mode, and with PCIe ASPM disabled, so it
  # is not a power or link-management problem. Protectli publishes an older
  # firmware build for this card batch (wifi-fix-standalone-0.3.1.tar from
  # kb.protectli.com). With it the card probes cleanly:
  #
  #   firmware ver RM.4.4.1.c2-00057-QCARMSWP-1 api 6 ...
  #   htt-ver 3.56 wmi-op 4 htt-op 3 cal otp max-sta 32 ...
  #   ath10k_pci 0000:07:00.0 wlp7s0: renamed from wlan0
  #
  # The blobs are vendored under ../firmware/qca6174 rather than fetched:
  # this is load-bearing hardware firmware, a third-party URL disappearing
  # would break the build, and the box has to build and boot offline.
  #
  # NixOS merges hardware.firmware through pkgs.buildEnv and zstd-compresses
  # every file, so these collide with linux-firmware's copies by name
  # (board-2.bin.zst). buildEnv keeps the first match in list order, so
  # mkBefore is what makes this override actually take effect.
  hardware.firmware = lib.mkBefore [
    (pkgs.runCommand "qca6174-firmware-protectli" {} ''
      install -Dm644 ${../firmware/qca6174/board-2.bin} \
        $out/lib/firmware/ath10k/QCA6174/hw3.0/board-2.bin
      install -Dm644 ${../firmware/qca6174/firmware-6.bin} \
        $out/lib/firmware/ath10k/QCA6174/hw3.0/firmware-6.bin
      install -Dm644 ${../firmware/qca6174/notice_ath10k_firmware-6.txt} \
        $out/lib/firmware/ath10k/QCA6174/hw3.0/notice_ath10k_firmware-6.txt
    '')
  ];
}
