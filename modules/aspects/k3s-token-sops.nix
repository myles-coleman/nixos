{
  # k3s tokens come from the shared sops ciphertext (secrets/common.yaml).
  #
  # A cluster has exactly ONE agent token: k3s stores it as the single `node`
  # password (pkg/daemons/control/deps/deps.go, `getNodePass`), so agents cannot
  # have per-node tokens. Setting `--agent-token` on the server replaces that
  # password, which is why the agents are moved onto the agent token in the same
  # change rather than left on the server token.
  #
  # The server token stays on the control plane; agents present the agent token,
  # which cannot be used to join as a server.
  #
  # The right token is chosen by role, so server and agent hosts both list this one
  # aspect. (The microvm sandbox node deliberately does NOT list it — it reads a
  # distinct, scoped token from its own ciphertext so it never decrypts the server
  # token.)
  flake.modules.nixos.k3s-token-sops = {
    config,
    lib,
    ...
  }: {
    sops.secrets.k3s_server_token = {
      sopsFile = ../../secrets/common.yaml;
      owner = "root";
      mode = "0600";
      restartUnits = ["k3s.service"];
    };

    sops.secrets.k3s_agent_token = {
      sopsFile = ../../secrets/common.yaml;
      owner = "root";
      mode = "0600";
      # Deliberately NOT restarted automatically. Setting --agent-token makes k3s
      # rewrite `server/cred/passwd`; if a restart lands between that write and the
      # datastore reconcile, k3s then refuses to start with
      #   "passwd newer than datastore and could cause a cluster outage.
      #    Remove the file(s) from disk and restart to be recreated from datastore."
      # and the API server stays down (this took the cluster out once). Rotating the
      # agent token is a documented manual step instead.
      restartUnits = [];
    };

    # Install secrets from a SERVICE ordered before k3s, not from the stage-2
    # activation script. `--agent-token-file` must exist before k3s starts — a
    # missing file makes k3s exit immediately — and activation ordering is not a
    # reliable guarantee of that.
    sops.useSystemdActivation = true;

    services.k3s.tokenFile =
      if config.services.k3s.role == "server"
      then config.sops.secrets.k3s_server_token.path
      else config.sops.secrets.k3s_agent_token.path;

    # The token must be decrypted before k3s starts.
    systemd.services.k3s.after = ["sops-install-secrets.service"];
    systemd.services.k3s.wants = ["sops-install-secrets.service"];
  };
}
