# Task 01 Proofs - Host Definition, Base System, and Remote Deployment

## Task Summary

This task adds the `protecli-vault` host to the NixOS flake as a self-contained configuration with a base system, home-manager, SSH, Tailscale, Docker, and remote deployment support via `rebuild.sh --protecli-vault`. A placeholder `hardware-configuration.nix` allows the flake to evaluate before the physical device is available.

## What This Task Proves

- The `protecli-vault` host is defined in `flake.nix` following the homelab/bee-gpu-server self-contained pattern.
- The flake evaluates successfully with all host modules (including stub networking, firewall, and services modules).
- The `rebuild.sh` script supports `--protecli-vault` for remote deployment to `bee@192.168.100.1`.
- All code passes `alejandra` formatting checks.

## Evidence Summary

- The flake dry-run produces 57 derivations with zero errors, confirming structural correctness.
- The `flake.nix` diff shows the new entry following the exact homelab pattern.
- The `rebuild.sh` diff shows the new flag, host variable, and deploy block.
- `alejandra --check .` passes with no formatting issues.

## Artifact: Flake dry-run evaluation

**What it proves:** The `protecli-vault` NixOS configuration is structurally valid and evaluates without errors.

**Why it matters:** This confirms all imports resolve, module signatures are correct, and the configuration is buildable.

**Command:**

```bash
nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run
```

**Result summary:** The command completed successfully, listing 57 derivations to be built and 3 paths to be fetched. No errors.

```
these 57 derivations will be built:
  /nix/store/...-firewall-start.drv
  /nix/store/...-nixos-system-protecli-vault-25.05.20260102.ac62194.drv
  ...
these 3 paths will be fetched (0.10 MiB download, 0.30 MiB unpacked):
  /nix/store/...-iperf-3.19.1
  ...
```

## Artifact: flake.nix diff

**What it proves:** The `protecli-vault` entry follows the homelab/bee-gpu-server self-contained pattern (unstable overlay + home-manager + host module, no `commonModules`).

**Why it matters:** Confirms the host is correctly integrated into the flake without importing desktop/gaming/dev-tools modules.

```diff
+      protecli-vault = nixpkgs.lib.nixosSystem {
+        inherit system;
+        modules = [
+          {nixpkgs.overlays = [unstableOverlay];}
+          home-manager.nixosModules.default
+          ./hosts/protecli-vault
+        ];
+      };
```

## Artifact: rebuild.sh diff

**What it proves:** Remote deployment is integrated with `--protecli-vault` flag targeting `bee@192.168.100.1` (management port).

**Why it matters:** Confirms the user can deploy to the Vault using the same `rebuild.sh` workflow as homelab and pikvm.

```diff
+PROTECLI_VAULT_HOST="bee@192.168.100.1"
 ...
+PROTECLI_VAULT=false
 ...
+        --protecli-vault) PROTECLI_VAULT=true ;;
 ...
+elif $PROTECLI_VAULT; then
+    # Build locally, deploy to protecli-vault
+    nixos-rebuild "$ACTION" --flake .#protecli-vault \
+        --target-host "$PROTECLI_VAULT_HOST" \
+        --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)
```

## Artifact: alejandra formatting check

**What it proves:** All `.nix` files comply with the repository's `alejandra` formatter.

**Why it matters:** Repository standard requires `alejandra` formatting; this confirms no violations.

**Command:**

```bash
alejandra --check .
```

**Result summary:** All 30 files pass formatting checks.

```
Checking style in 30 files using 8 threads.
Congratulations! Your code complies with the Alejandra style.
```

## Reviewer Conclusion

The `protecli-vault` host is correctly defined in the flake, evaluates without errors, includes remote deployment support via `rebuild.sh --protecli-vault`, and all code passes formatting checks. The placeholder `hardware-configuration.nix` will be replaced with real output from `nixos-generate-config` on the physical device.
