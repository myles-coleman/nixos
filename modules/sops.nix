{
  config,
  pkgs,
  lib,
  ...
}: {
  sops = {
    age.keyFile = "/etc/ssh/sops_key";
    defaultSopsFile = ../secrets/secrets.yaml;
  };
}
