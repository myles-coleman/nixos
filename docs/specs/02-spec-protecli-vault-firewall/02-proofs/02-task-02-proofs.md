# Task 02 Proofs - Network Interfaces, Bridge, and Routing with NAT

## Task Summary

This task configures the Protecli Vault's 6 Ethernet ports using systemd-networkd: 1 WAN (DHCP from ISP router), 4 LAN ports bridged into `br-lan` (10.0.0.1/24), and 1 management port on a separate subnet (192.168.100.1/24). IPv4 forwarding is enabled, systemd-resolved is disabled (DNS will be handled by Pi-hole + Unbound), and the default NixOS firewall/NAT modules are disabled in favor of custom nftables rules (Task 3.0).

## What This Task Proves

- systemd-networkd is used instead of NetworkManager for deterministic interface management.
- A `br-lan` bridge is created from 4 LAN interfaces using a reusable helper function.
- The WAN interface gets its IP via DHCP, the bridge gets 10.0.0.1/24, and the management port gets 192.168.100.1/24.
- IPv4 forwarding is enabled via kernel sysctl.
- The default NixOS firewall and NAT modules are disabled.
- systemd-resolved is disabled to avoid port 53 conflicts with Pi-hole.
- The flake evaluates successfully with all networking configuration.

## Evidence Summary

- The flake dry-run succeeds with 63 derivations including all expected systemd-networkd units (bridge netdev, 4 LAN enslavement networks, WAN, mgmt, br-lan).
- `alejandra --check .` passes with no formatting issues.
- Code review confirms all networking requirements are met.

## Artifact: Flake dry-run with networking module

**What it proves:** The networking configuration is structurally valid and integrates correctly with the host.

**Why it matters:** Confirms systemd-networkd units for all 6 interfaces, the bridge, and wait-online configuration are correctly defined.

**Command:**

```bash
nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run
```

**Result summary:** 63 derivations listed (up from 57 in Task 1.0). New derivations include:

- `unit-20-br-lan.netdev.drv` -- bridge device creation
- `unit-30-enp2s0.network.drv` through `unit-30-enp5s0.network.drv` -- 4 LAN interfaces enslaved to bridge
- `unit-10-wan.network.drv` -- WAN interface with DHCP
- `unit-10-mgmt.network.drv` -- management port with static 192.168.100.1/24
- `unit-40-br-lan.network.drv` -- bridge network with static 10.0.0.1/24
- `unit-50-tailscale.network.drv` -- Tailscale interface
- `unit-systemd-networkd.service.drv` -- systemd-networkd service
- `unit-systemd-networkd-wait-online.service.drv` -- wait-online with anyInterface

## Artifact: alejandra formatting check

**What it proves:** The networking module complies with repository formatting standards.

**Command:**

```bash
alejandra --check .
```

**Result summary:** All 30 files pass.

## Artifact: Code review of networking.nix

**What it proves:** All functional requirements for Unit 2 are addressed in the module.

**Key configuration elements:**

| Requirement | Implementation |
|---|---|
| systemd-networkd (not NetworkManager) | `networking.useNetworkd = true; networking.networkmanager.enable = false;` |
| WAN DHCP | `"10-wan"` network with `DHCP = "ipv4"` |
| br-lan bridge 10.0.0.1/24 | `"20-br-lan"` netdev + `"40-br-lan"` network with `address = ["10.0.0.1/24"]` |
| 4 LAN ports enslaved | `enslaveToBridge` helper applied to `[lan1 lan2 lan3 lan4]` |
| Management port 192.168.100.1/24 | `"10-mgmt"` network with `address = ["192.168.100.1/24"]` |
| IPv4 forwarding | `boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true` |
| Disable NixOS firewall/NAT | `networking.firewall.enable = lib.mkForce false; networking.nat.enable = false;` |
| Disable systemd-resolved | `services.resolved.enable = false;` |
| Dynamic interface handling | `systemd.network.wait-online.anyInterface = true;` |

**Note:** NAT masquerade rule will be placed in `firewall.nix` (Task 3.0) alongside the filter rules, as specified in sub-task 2.11.

## Reviewer Conclusion

The networking module correctly configures all 6 Ethernet ports with systemd-networkd, creates the br-lan bridge, enables IPv4 forwarding, and disables conflicting NixOS defaults. The module uses a clean helper function pattern for bridge enslavement. Interface names are clearly marked as placeholders. The NAT masquerade rule is deferred to firewall.nix for co-location with filter rules.
