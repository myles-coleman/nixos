{
  config,
  pkgs,
  lib,
  ...
}: {
  # SDL2 environment variable for Joy-Con button mapping (positional instead of label-based)
  environment.variables = {
    SDL_GAMECONTROLLER_USE_BUTTON_LABELS = "0";
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
    opencodeV2 # opencode v2 (pinned flake input), replaces unstable.opencode
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
    remmina
    wvkbd
    # maliit-framework
    python3
    typora
    bat
  ];
}
