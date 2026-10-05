{
  config,
  pkgs,
  lib,
  ...
}: {
  users.users.bee = {
    initialPassword = "raspberry";
    isNormalUser = true;
    extraGroups = ["wheel" "video" "input" "networkmanager"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFwn9u4rjBjifRODlycmjtEJRKfV2bSnwvDa5sC5Hpp bee@bee-gpd"
      # CI deploy key (public half of the `SSH_PRIVATE_KEY` Environment secret)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzbHiGJguieUhUnv5ktHoLjOhN9TqEUJS/zwDFZqrsC github-actions"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # deploy-rs copies the CI-built closure as `bee` over `ssh-ng://`; the target
  # must trust that user or `require-sigs = true` rejects the unsigned paths.
  nix.settings.trusted-users = ["root" "bee"];

  # Password auth is intentionally preserved from the source repo even though
  # the old AGENTS.md claimed key-only access (see task 3.6).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };
}
