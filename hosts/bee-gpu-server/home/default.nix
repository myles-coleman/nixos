{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.users.${mainUser} = {
    # Basic Plasma/KDE home-manager configuration
    home.packages = with pkgs; [
      # Additional KDE applications can be added here
      kdePackages.konsole
      kdePackages.gwenview
      kdePackages.ark
    ];

    # Plasma-specific settings can be added here using home-manager's plasma module
    # or through plasma-manager if integrated in the future
  };
}
