# `modules/aspects/` — flake-parts aspect registry

This directory is the module registry for the x86_64 fleet. Each `*.nix` file
here is a flake-parts module that contributes one or more **aspects** to the
class-tagged `config.flake.modules` store. A host is composed by **listing** the
aspects it wants: *listed = enabled*.

The registry is auto-imported by `import-tree ./modules/aspects` in `flake.nix`;
adding a file here registers its aspects with no edits to `flake.nix`.

## What an aspect is

- A file may define `config.flake.modules.nixos.<name>` (a NixOS module) and,
  where the concern has a Home Manager half,
  `config.flake.modules.homeManager.<name>` (a Home Manager module).
- Multiple files may contribute to the same `<name>`; flake-parts merges them
  with `deferredModule` semantics.
- `config.flake.modules` is class-tagged: importing a `homeManager` module into
  a NixOS configuration is a type error. This comes from
  `flake-parts.flakeModules.modules`, imported in `flake-parts.nix`.

## Rules

1. **Listed = enabled.** A host enables a capability by importing the aspect.
   There are no `enable` options, and no conditional imports (`imports` cannot
   depend on `config`).
2. **Cross-class concerns live in one file.** A concern with both a NixOS and a
   Home Manager half defines both aspects in the same file (see `home-zsh.nix`).
3. **The NixOS half owns the user and the globals.** `home-manager.useGlobalPkgs`,
   `useUserPackages`, `backupFileExtension`, and the `home-manager.users.<user>`
   entry are NixOS options: they belong in the `nixos` half, which wires the
   `homeManager` half in via `home-manager.users.<user>.imports`. The
   `homeManager` half must never set a `home-manager.*` option.
4. **Reference `config.flake.modules`, never `inputs.self`.** Composition inside
   an aspect uses the flake-level `config` (closed over in a `let` if the inner
   NixOS module argument would shadow it). Host aspects are imported explicitly
   in `flake.nix` because `import-tree` only scans `modules/aspects/**`.
5. **Helpers are not modules.** `import-tree` ignores any path containing `/_`;
   put shared helper code under a `_`-prefixed directory.

## Adding an aspect

1. Create `modules/aspects/<name>.nix`:

   ```nix
   {
     flake.modules.nixos.<name> = {pkgs, ...}: {
       environment.systemPackages = with pkgs; [ ... ];
     };
   }
   ```

2. To enable it on a host, add `<name>` to that host aspect's
   `imports = [ ... (with aspects; [ <name> ]) ];`.
3. Type-check everything (including aspects no host lists yet) with
   `nix eval .#checks.x86_64-linux.all-aspects` and
   `nix flake check --no-build`.
4. Verify closure preservation with
   `nix store diff-closures <old-toplevel> <new-toplevel>` (no added/removed
   packages), not the name-only CI diff.

## Shared user and network aspects (spec 17)

Spec 17 extracted the blocks that were copy-pasted across hosts into four
invariant-only aspects:

- `access.nix` — the `bee` user base (`isNormalUser`/`description`/`shell`),
  `programs.zsh.enable`, and the `services.openssh` block. It deliberately does
  **not** set `extraGroups`, `openssh.authorizedKeys.keys`, user `packages`, or
  any sudo rule (those differ per host). Because `common.nix` also declares the
  user base for hosts that must not gain sshd/sudo, `access` re-declares the
  unique-merge scalars at priority 500: `common`'s normal definition wins where
  both are listed, and `access` alone beats the built-in bash-shell default.
- `sudo.nix` — the passwordless `security.sudo.extraRules` entry for `bee`.
  `security.sudo.extraRules` concatenates, so a host that lists `sudo` must
  remove any inline rule.
- `tailscale.nix` — the `services.tailscale` invariants (`enable`, `package =
  pkgs.unstable.tailscale`, `openFirewall`); it composes `unstable`. Scalar
  settings such as `useRoutingFeatures`, `authKeyFile`, and the extra flags stay
  host-local.
- `networkmanager.nix` — `networking.networkmanager.enable = true`. Scalar
  settings such as `dns` stay host-local (or in `network`).

`network.nix` now **composes** `networkmanager` + `tailscale` and retains only
its desktop deltas (systemd-resolved DNS backend, `useRoutingFeatures = "both"`,
Mullvad, avahi, rpcbind). This is the reference example of one aspect importing
others.

Because `network` transitively applies `networkmanager` and `tailscale`, those
two names are intentionally **not** listed in the `all-aspects` allowlist: the
NixOS module system applies a module once per reference, so listing them
directly *and* transitively would define unique options twice. They are still
fully type-checked through `network`.

## Host-local modules (`hosts/<host>/modules/`)

Host-local concerns that do not belong in a shared aspect live in
`hosts/<host>/modules/*.nix` and are imported explicitly from
`hosts/<host>/default.nix` (plain imports; `import-tree` only scans
`modules/aspects/**`). Each module takes only `{config, pkgs, lib, ...}` and must
not receive `inputs` or the flake-level `config`; any `inputs.*` or
`config.flake.modules` reference stays in `hosts/<host>/default.nix`. Moving a
file into `modules/` adds one directory level, so re-base relative imports
(`../../modules/...` → `../../../modules/...`, `../../secrets/...` →
`../../../secrets/...`). `hosts/protecli-vault/modules/` was the original
reference; spec 17 applied the same pattern to `bee-gpu-server`, `homelab`,
`bee-gpd`, and `rpi3`.

## Host aspects

A host aspect lives at `hosts/<host>/default.nix` and defines
`config.flake.modules.nixos.<host>`, listing the aspects it composes plus its
host-local plain imports (`hardware-configuration.nix`, `../../modules/sops.nix`,
host-specific modules). It is a full NixOS configuration, so it is **not**
merged into the synthetic `all-aspects` check. Hosts list a package-providing
aspect (for dedup) only when every package it provides is already in the host's
closure; hosts never gain a package from a dedup aspect.

## Status and deferred scope

All five x86_64 hosts are aspect-composed: spec 14 converted the `homelab`
pilot, and spec 15 converted `bee-pc`, `bee-gpd`, `bee-gpu-server`, and
`protecli-vault`. Shared concerns that used to live as wholesale-imported
`modules/*.nix` files (`common`, `desktop`, `networking`, `dev-tools`, `gaming`,
`nvidia`, `home`) are now aspects, and the legacy files were removed.

The RPi k3s fleet (`node0`–`node4`) and the `rpi3` kiosk are also
aspect-composed as of spec 16. Their shared concerns are **flat** aspects
(`rpi-base`, `k3s-common`, `k3s-server`, `k3s-agent`, `k3s-token-sops`,
`node-health`) ported verbatim from the former `modules/rpi/*.nix`; each host
lists every leaf aspect it enables. Because flattening removed the former
`k3s-server → k3s-common → node-health` import edges, the k3s role aspects carry
an evaluation-time assertion (`k3sCommon.enabled`) that fails loudly if a role is
listed without `k3s-common`. The RPi host-aspect shape differs from the x86 shape
in that it has **no `hardware-configuration.nix`** — vendor board/kernel modules
(`raspberry-pi-5.base`, `page-size-16k`, `raspberry-pi-3.base`, `sd-image`) are
plain host imports or live inside `rpi-base`, and `specialArgs = inputs` is
retained on the vendor `nixos-raspberrypi.lib.nixosSystem` calls. `disko-config.nix`
and `modules/sops.nix` remain plain host imports.

Still out of scope:

- the unmerged spec 11 `my.roles.*` abstraction (PR #17) is superseded and never
  lands;
- migrating `pikvm`, which is aarch64 but not on the vendor
  `nixos-raspberrypi` library (it uses the plain `nixpkgs.lib.nixosSystem` path);
- a synthetic aarch64 `all-aspects` check — dropped as non-composable and
  redundant with the `build-arm` lane that builds every RPi host;
- a typed `configurations.nixos.<host>.module` registry (spec 14's
  `flake.modules.nixos.<host>` shape is retained for all hosts); this is a
  possible future spec.

`modules/sops.nix` stays path-imported (a plain module), as do
`modules/steam-remote-play-client.nix` and `modules/pikvm.nix`.
