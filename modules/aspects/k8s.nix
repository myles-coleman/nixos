{
  flake.modules.nixos.k8s = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      kubectl
      kustomize
      k9s
    ];
  };
}
