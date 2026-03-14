{
  config,
  pkgs,
  lib,
  ...
}: {
  environment.sessionVariables = {
    AWS_PROFILE = "homelab";
  };

  environment.systemPackages = with pkgs; [
    kubectl
    kustomize
    wl-clipboard
    jq
    kubernetes-helm
    helmfile
    k9s
    docker
    terraform
    unstable.opentofu
    terragrunt
    awscli2
    nixos-anywhere
    argocd
    go-task
    nodejs_20
    dig
    slack
  ];
}
