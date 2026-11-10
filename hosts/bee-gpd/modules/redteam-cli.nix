{pkgs, ...}: let
  cli = pkgs.callPackage ../../../pkgs/redteam-cli {};
  evidence = pkgs.callPackage ../../../pkgs/redteam-evidence {};
in {
  # Spec 31, Unit 5: operator-side tools. The private key, client key, and
  # pinned server certificate live in ~/.config/redteam/, not in the Nix store.
  environment.systemPackages = [cli evidence];
}
