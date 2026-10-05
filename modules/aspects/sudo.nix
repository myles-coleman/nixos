{
  flake.modules.nixos.sudo = {...}: {
    # Allow passwordless sudo for remote deploys. Listed only by hosts that
    # already had this rule; `security.sudo.extraRules` concatenates, so a
    # listing host must not also define its own rule.
    security.sudo.extraRules = [
      {
        users = ["bee"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };
}
