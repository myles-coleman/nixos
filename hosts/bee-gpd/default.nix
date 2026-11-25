{
  config,
  inputs,
  ...
}: let
  aspects = config.flake.modules.nixos;
in {
  flake.modules.nixos.bee-gpd = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports =
      [
        ./hardware-configuration.nix
        ./home
        # ./modules/egpu.nix
        ./modules/input.nix
        ./modules/automation.nix
        ./modules/networking.nix
        ./modules/packages.nix
        # Spec 31, Unit 5: redteam-cli and the evidence verifier.
        ./modules/redteam-cli.nix
        ../../modules/sops.nix
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.default
      ]
      ++ (with aspects; [
        access
        common
        desktop
        home-desktop
        home-zsh
        network
        dev-tools
        gaming
        nvidia
        unstable
      ]);

    # MagicDNS. The transcriber is reached as
    # https://bee-gpu-server.tail6d2e9b.ts.net, and without this the name does
    # not resolve: tailscaled had no DNS rights, so systemd-resolved answered
    # NXDOMAIN while `dig @100.100.100.100` resolved fine.
    #
    # Scoped to this host on purpose. It rewrites the host resolver to the
    # tailnet's (which forwards upstream), and the cluster nodes have their own
    # DNS story through k3s; promote it to the `tailscale` aspect only if every
    # machine should have MagicDNS.
    services.tailscale.extraSetFlags = ["--accept-dns=true"];

    # nixpkgs builds CONFIG_ACPI_TINY_POWER_BUTTON as a module next to
    # CONFIG_ACPI_BUTTON, so it autoloads on the ACPI power button. It turns
    # the firmware's power-button notify on s2idle wake into SIGRTMIN+4 to
    # PID 1, so every lid-open resume powers the machine off. The real power
    # button keeps working through `button` + logind. Keep this until nixpkgs
    # stops building the module.
    # https://github.com/NixOS/nixpkgs/issues/577729
    boot.blacklistedKernelModules = ["tiny_power_button"];
    boot.loader.systemd-boot.enable = true;
    # Kept at 1 on purpose: the 100 MB ESP is shared with Windows (49 MB) and one
    # NixOS generation costs ~40 MB (13 MB kernel + 27 MB initrd). The boot loader
    # builder deletes dropped generations *before* copying the new one, so any
    # value above 1 makes the next kernel or initrd change fail with ENOSPC.
    # Rollback depth needs a larger ESP or a separate XBOOTLDR partition
    # (spec 32 follow-up), not this knob.
    boot.loader.systemd-boot.configurationLimit = 1;
    boot.loader.efi.canTouchEfiVariables = true;
    networking.hostName = "bee-gpd";
    users.users.bee.extraGroups = ["video"];
    system.stateVersion = "25.05";
  };
}
