{
  config,
  pkgs,
  lib,
  ...
}: {
  environment.sessionVariables = {
    AWS_PROFILE = "homelab";
    PRISMA_QUERY_ENGINE_LIBRARY = "${pkgs.prisma-engines}/lib/libquery_engine.node";
    PRISMA_QUERY_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/query-engine";
    PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/schema-engine";
  };

  environment.systemPackages = with pkgs; [
    prisma-engines
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
    uv
    openssl
    ranger
  ];
}
