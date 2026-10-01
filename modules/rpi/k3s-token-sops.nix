{config, ...}: {
  # k3s server token comes from the shared sops ciphertext (program Phase 3
  # staged `k3s_server_token` in `secrets/common.yaml` for these recipients).
  # This replaces the old build-time placeholder + deploy-time SSH injection.
  sops.secrets.k3s_server_token = {
    sopsFile = ../../secrets/common.yaml;
    owner = "root";
    mode = "0600";
    restartUnits = ["k3s.service"];
  };

  services.k3s.tokenFile = config.sops.secrets.k3s_server_token.path;

  # The token must be decrypted before k3s starts.
  systemd.services.k3s.after = ["sops-install-secrets.service"];
  systemd.services.k3s.wants = ["sops-install-secrets.service"];
}
