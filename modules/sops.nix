{
  config,
  pkgs,
  lib,
  ...
}: {
  # Each host selects its own ciphertext via `sops.defaultSopsFile`.
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # The per-host age key is provisioned out-of-band at this path. Only the
  # directory is created declaratively; the key file itself is never generated
  # by the module. Ordering after tmpfiles ensures the directory exists first.
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root -"
  ];

  systemd.services.sops-install-secrets = {
    after = ["systemd-tmpfiles-setup.service"];
    wants = ["systemd-tmpfiles-setup.service"];
  };
}
