{
  config,
  pkgs,
  lib,
  ...
}: {
  # Basic sops-nix configuration
  sops = {
    # The default file where all secrets are stored
    defaultSopsFile = /secrets/secrets.yaml;

    # The age key used to decrypt the secrets
    # This should point to a file containing your private age key
    age.keyFile = /etc/ssh/sops_key;
  };
}
