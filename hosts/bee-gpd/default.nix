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
  environment.sessionVariables = {
    SDL_GAMECONTROLLER_USE_BUTTON_LABELS = "0";
  };

  # Thunderbolt support
  services.hardware.bolt.enable = true;
  services.udev.packages = with pkgs; [
    bolt
  ];

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

  system.stateVersion = "25.05";
}
