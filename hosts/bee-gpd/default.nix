{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./home
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable IOMMU
  boot.kernelParams = ["amd_iommu=on" "iommu=pt"];

  # Kernel modules for game controllers
  boot.kernelModules = ["hid_nintendo" "joydev"];

  networking.hostName = "bee-gpd";

  # Extra groups specific to bee-gpd
  users.users.bee.extraGroups = ["video"];

  # Enable joystick support
  hardware.uinput.enable = true;

  # SDL2 environment variable for Joy-Con button mapping (positional instead of label-based)
  environment.variables = {
    SDL_GAMECONTROLLER_USE_BUTTON_LABELS = "0";
  };

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

  # Ollama needs the eGPU driver loaded before it can use CUDA
  systemd.services.ollama = {
    after = ["nvidia-egpu.service"];
    wants = ["nvidia-egpu.service"];
  };

  # udev rules for eGPU hotplug + Joy-Con hidraw access
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TAG+="systemd", ENV{SYSTEMD_WANTS}="nvidia-egpu.service"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", SUBSYSTEMS=="hid", DRIVERS=="nintendo", MODE="0660", GROUP="input", TAG+="uaccess"
  '';

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

  # tmux config
  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      tmuxPlugins.sensible
    ];
  };

  environment.systemPackages = with pkgs; [
    brightnessctl #brightness control
    calibre
    ethtool
    tmux
    zsh-autosuggestions
    toybox #gives unix utilities like `killall`
    pcmanfm #file manager
    python313Packages.cmake
    mpv
    unstable.opencode
    ollama
    ffmpeg
    redshift #blue light filter
    freecad
    linuxConsoleTools #includes jstest for joystick testing
    evtest #for testing input events
    SDL2 #required for proper gamepad support in emulators
    wl-clipboard #clipboard sharing with Waydroid
    unstable.claude-code
    zathura
    unstable.prismlauncher
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Ensure opencode npm dependencies are installed
  systemd.user.services.opencode-setup = {
    description = "Install opencode npm dependencies";
    wantedBy = ["default.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p $HOME/.cache/opencode && echo '\"'\"'{\"dependencies\":{\"@ai-sdk/openai-compatible\":\"1.0.31\"}}'\"'\"' > $HOME/.cache/opencode/package.json && cd $HOME/.cache/opencode && ${pkgs.nodejs}/bin/npm install'";
    };
  };

  # Android emulator via Waydroid (LXC container)
  # https://wiki.nixos.org/wiki/Waydroid
  virtualisation.waydroid.enable = true;

  system.stateVersion = "25.05";
}
