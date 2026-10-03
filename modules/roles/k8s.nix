{
  config,
  pkgs,
  lib,
  ...
}: {
  options.my.roles.k8s.enable = lib.mkEnableOption "shared Kubernetes tooling (kubectl, kustomize, k9s)";

  config = lib.mkIf config.my.roles.k8s.enable {
    environment.systemPackages = with pkgs; [
      kubectl
      kustomize
      k9s
    ];
  };
}
