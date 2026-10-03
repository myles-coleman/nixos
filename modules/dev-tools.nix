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
    wl-clipboard
    jq
    kubernetes-helm
    helmfile
    docker
    terraform
    unstable.opentofu
    terragrunt
    awscli2
    nixos-anywhere
    argocd
    go-task
    nodejs_24
    dig
    slack
    uv
    openssl
  ];
}
