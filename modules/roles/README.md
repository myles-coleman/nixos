# `my.roles.*` role modules

Shared, enable-gated package lists for the monorepo. Each role is a NixOS module
that declares `my.roles.<role>.enable` and contributes its packages only when
enabled. The aggregator `modules/roles/default.nix` imports every role; add
`./modules/roles` to a host's module list (or to `commonModules`) so the options
exist, then opt in per host:

```nix
my.roles.cli-core.enable = true;
```

## Roles

| Role | Packages |
| --- | --- |
| `cli-core` | `vim`, `htop`, `tree`, `alejandra`, `gh` |
| `cli-extras` | `wget`, `fastfetch`, `gnumake`, `ranger` |
| `server-base` | `git`, `curl`, `tldr`, `gcc`, `gnupg`, `lm_sensors` |
| `k8s` | `kubectl`, `kustomize`, `k9s` |
| `fonts` | `noto-fonts`, `noto-fonts-cjk-sans`, `noto-fonts-color-emoji`, `nerd-fonts.meslo-lg`, `font-awesome` |
| `home-zsh` | shared home-manager zsh + oh-my-posh setup |

## Closure-preservation rule

Roles exist to remove duplication without changing what a host builds. Enable a
role on a host **only** when that host's existing package set already contains
every package the role provides. A role must never add or remove a package, and
package-name normalization (for example `opentofu` vs `unstable.opentofu`) is out
of scope for a role refactor. Verify with a per-host closure diff
(`nix path-info -r` name comparison or `nix store diff-closures`) showing no
additions or removals.
