{
  flake.modules.nixos.access = {
    config,
    lib,
    pkgs,
    ...
  }: {
    # `common` also declares the `bee` user base for hosts that must not gain
    # sshd/sudo (e.g. bee-pc). These scalar options are unique-merge, so `access`
    # re-declares them:
    #   - priority 500 beats the built-in `users-groups.nix` `mkDefault` bash
    #     shell (1000) on hosts that list `access` without `common`;
    #   - `common`'s normal-priority (100) definition still wins on hosts that
    #     list both (identical value), so there is no conflict.
    users.users.bee = {
      isNormalUser = lib.mkDefault true;
      description = lib.mkOverride 500 "bee";
      shell = lib.mkOverride 500 pkgs.zsh;
    };

    programs.zsh.enable = true;

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
      };
    };
  };
}
