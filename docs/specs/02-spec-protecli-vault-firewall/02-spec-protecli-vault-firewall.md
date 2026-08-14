# 02-spec-protecli-vault-firewall.md

## Introduction/Overview

Add a new NixOS host called `protecli-vault` to the existing flake configuration, turning a Protectli FW6C (6-port Intel i5-7200U) into a network firewall/router. This foundational spec covers getting the machine into the flake with basic WAN/LAN routing, NAT, nftables firewall, DHCP, DNS (Pi-hole + Unbound), SSH management access, Tailscale, and remote deployment via `rebuild.sh`. The Vault will initially sit behind the ISP router (double-NAT) for safe development and testing.

## Goals

- Define the `protecli-vault` host in `flake.nix` as a self-contained NixOS configuration (following the homelab/pikvm pattern, not using shared `commonModules`)
- Configure 6 Ethernet ports: 1 WAN, 4 bridged LAN (`br-lan`), 1 dedicated management port
- Establish basic IPv4 routing with NAT (masquerade) and nftables firewall rules
- Provide DHCP and DNS services to LAN clients via Pi-hole (using its built-in DHCP server and DNS ad blocking)
- Provide recursive DNS resolution via Unbound as Pi-hole's upstream resolver
- Enable SSH access on all interfaces (LAN, management, Tailscale), with the management port providing a guaranteed fallback that is immune to firewall misconfigurations on other interfaces
- Integrate with `rebuild.sh` for remote deployment (`--protecli-vault` flag)
- Enable basic Tailscale client for remote management access

## User Stories

- **As a home network administrator**, I want a dedicated NixOS-based firewall appliance so that my network security is managed declaratively and version-controlled in git.
- **As a home network administrator**, I want a dedicated management port on the Vault so that I can always SSH in to fix firewall misconfigurations without being locked out.
- **As a home network administrator**, I want the Vault to serve DHCP and DNS to LAN clients so that devices on my network automatically get IP addresses and ad-free DNS resolution.
- **As a home network administrator**, I want to deploy configuration changes remotely from my development machine so that I do not need physical access to the Vault for routine updates.
- **As a home network administrator**, I want the Vault to sit behind my ISP router initially so that I can develop and test the configuration without disrupting my existing network.

## Demoable Units of Work

### Unit 1: Host Definition and Base System

**Purpose:** Get the Protecli Vault defined in the flake, booting with a minimal NixOS configuration, and deployable via `rebuild.sh --protecli-vault`.

**Functional Requirements:**
- The system shall define a `protecli-vault` entry in `flake.nix` under `nixosConfigurations` as a self-contained x86_64-linux host (not using `commonModules`), following the homelab/bee-gpu-server pattern
- The system shall include `hosts/protecli-vault/default.nix` with base system settings: hostname, user `bee` with zsh shell, locale, timezone, nix flakes enabled, unfree packages allowed, `stateVersion = "25.05"`
- The system shall include `hosts/protecli-vault/hardware-configuration.nix` (generated on the device via `nixos-generate-config`)
- The system shall enable SSH with `PermitRootLogin = "no"` and passwordless sudo for user `bee` (required for remote `nixos-rebuild`)
- The `rebuild.sh` script shall support a `--protecli-vault` flag that deploys via `nixos-rebuild $ACTION --flake .#protecli-vault --target-host $PROTECLI_VAULT_HOST --use-remote-sudo`. The `PROTECLI_VAULT_HOST` variable shall default to the management port IP (e.g., `bee@192.168.100.1`). Remote deploys can also be performed via the LAN IP (`10.0.0.1`) or the Tailscale IP when reachable, by overriding the variable or editing `rebuild.sh`
- The system shall include a minimal home-manager configuration for user `bee` with zsh and oh-my-posh (following the homelab/bee-gpu-server pattern)

**Proof Artifacts:**
- CLI: `rebuild.sh --protecli-vault --dry-run` completes successfully demonstrates the host is defined in the flake and builds without errors
- CLI: `ssh bee@<vault-ip> hostname` returns `protecli-vault` demonstrates SSH access and base system configuration
- CLI: `ssh bee@<vault-ip> nix --version` returns a nix version demonstrates flakes are enabled

### Unit 2: Network Interfaces, Routing, and NAT

**Purpose:** Configure the 6 Ethernet ports for their assigned roles (WAN, LAN bridge, management) and enable IPv4 routing with NAT so LAN clients can reach the internet.

**Functional Requirements:**
- The system shall use `systemd-networkd` (not NetworkManager) for deterministic interface management
- The system shall configure one interface as the WAN port, obtaining its IP via DHCP from the upstream ISP router
- The system shall bridge 4 interfaces into a `br-lan` bridge with a static IP of `10.0.0.1/24`
- The system shall configure one interface as a management port with a static IP on a separate subnet (e.g., `192.168.100.1/24`)
- The system shall enable IPv4 forwarding via `boot.kernel.sysctl` (`net.ipv4.conf.all.forwarding = true`)
- The system shall configure NAT masquerade via nftables so that traffic from `br-lan` is source-NATed when leaving the WAN interface
- The system shall NOT use `networking.nat` or `networking.firewall` (the default NixOS firewall modules) -- all firewall and NAT rules shall be managed via `networking.nftables` with custom rulesets

**Proof Artifacts:**
- CLI: `ip addr show br-lan` shows `10.0.0.1/24` assigned demonstrates bridge is configured correctly
- CLI: `ip addr show <mgmt-interface>` shows `192.168.100.1/24` demonstrates management port is on a separate subnet
- CLI: `sysctl net.ipv4.ip_forward` returns `1` demonstrates IP forwarding is enabled
- CLI: `nft list ruleset` shows NAT masquerade rule for the WAN interface demonstrates NAT is configured
- CLI: from a LAN client, `ping 8.8.8.8` succeeds demonstrates end-to-end routing through the Vault

### Unit 3: nftables Firewall Rules

**Purpose:** Establish a secure firewall that protects the Vault and LAN while allowing legitimate traffic to flow.

**Functional Requirements:**
- The system shall use `networking.nftables.enable = true` with the default NixOS firewall disabled (`networking.firewall.enable = false`)
- The nftables ruleset shall implement an `inet filter` table with `input`, `forward`, and `output` chains
- The `input` chain shall: accept all traffic from `br-lan` (including SSH), accept all traffic from the management interface, accept traffic from `tailscale0`, accept established/related traffic from WAN, accept ICMP (echo-request, destination-unreachable, time-exceeded) from WAN, drop all other WAN input
- The `forward` chain shall: accept traffic from `br-lan` to WAN, accept established/related traffic from WAN back to `br-lan`, drop all other forwarded traffic
- The management interface's accept rule shall be placed at the top of the `input` chain (evaluated first), ensuring SSH access survives any misconfiguration of LAN or WAN rules below it
- The nftables ruleset shall log dropped packets with a configurable rate limit for debugging

**Proof Artifacts:**
- CLI: `nft list ruleset` shows the complete filter and NAT tables demonstrates firewall rules are applied
- CLI: from WAN side, `nmap -p 22 <vault-wan-ip>` shows port 22 filtered/closed demonstrates WAN is locked down
- CLI: from management port, `ssh bee@192.168.100.1` succeeds demonstrates management access works independently
- CLI: `journalctl -k | grep "dropped"` shows logged dropped packets demonstrates firewall logging works

### Unit 4: DHCP and DNS Services (Pi-hole + Unbound)

**Purpose:** Provide DHCP address assignment and DNS resolution with ad blocking to LAN clients. Pi-hole handles both DHCP and DNS in a single service, eliminating the need for a separate dnsmasq instance.

**Architecture overview:** Pi-hole runs as a Docker container and provides two services: (1) a DHCP server that assigns IP addresses and advertises itself as the DNS server and default gateway, and (2) a DNS server with ad-blocking that forwards non-blocked queries to Unbound. Unbound runs as a native NixOS service performing recursive DNS resolution directly against root nameservers, so no external DNS providers (Cloudflare, Google) are used.

```
LAN Client --> Pi-hole (DHCP: port 67, DNS: port 53) --> Unbound (recursive: port 5335) --> Root DNS
```

**Functional Requirements:**
- The system shall run Pi-hole as a Docker container, bound to the `br-lan` IP (`10.0.0.1`), handling both DNS (port 53) and DHCP (port 67)
- Pi-hole's built-in DHCP server shall serve leases on the `br-lan` interface with a range of `10.0.0.50` to `10.0.0.254` and a 24-hour lease time
- Pi-hole's DHCP shall advertise the Vault (`10.0.0.1`) as both the default gateway and DNS server
- Pi-hole's DHCP shall support static leases for known devices (homelab at `10.0.0.150`, pikvm at `10.0.0.175`) configured via the Pi-hole admin interface or environment/config files
- The system shall run Unbound as a native NixOS service (`services.unbound`) listening on `127.0.0.1:5335` for recursive DNS resolution
- Pi-hole shall be configured to use `127.0.0.1#5335` as its sole upstream DNS server (no external DNS providers)
- The nftables firewall shall allow DNS (UDP/TCP 53) and DHCP (UDP 67, 68) traffic on the `br-lan` interface
- The Pi-hole web admin interface shall be accessible from the LAN at `http://10.0.0.1/admin` (or a configured port)
- The system shall NOT run a separate dnsmasq service -- Pi-hole's embedded FTL engine (which is based on dnsmasq) handles both DHCP and DNS

**Proof Artifacts:**
- CLI: from a LAN client with no static IP, `ip addr` shows an IP in the `10.0.0.50-254` range demonstrates Pi-hole DHCP is working
- CLI: from a LAN client, `nslookup google.com 10.0.0.1` returns a valid IP demonstrates DNS resolution through Pi-hole and Unbound
- CLI: from a LAN client, `nslookup ads.example.com 10.0.0.1` returns `0.0.0.0` or NXDOMAIN demonstrates Pi-hole ad blocking is active
- CLI: `dig +short google.com @127.0.0.1 -p 5335` (on the Vault) returns a valid IP demonstrates Unbound recursive resolution works independently
- Browser: `http://10.0.0.1/admin` loads the Pi-hole dashboard demonstrates the web admin interface is accessible
- Browser: Pi-hole dashboard shows queries being blocked and DHCP leases being served demonstrates both services are integrated

## Non-Goals (Out of Scope)

1. **NixOS installation**: The spec assumes NixOS is already installed on the Vault. Installation is a one-time physical task handled separately.
2. **VLAN segmentation**: Network segmentation via VLANs (IoT, server, gaming VLANs) is a follow-up spec after basic routing is validated.
3. **WireGuard VPN**: Remote access VPN via WireGuard will be addressed in a separate spec.
4. **Suricata IDS/IPS**: Intrusion detection/prevention is a follow-up spec after the firewall foundation is stable.
5. **Tailscale exit node + Mullvad VPN**: Routing all network traffic through Tailscale as an exit node with Mullvad VPN requires its own dedicated spec due to complexity (split-tunnel decisions, DNS leak prevention, kill switches).
6. **Prometheus/Grafana monitoring**: Observability and metrics dashboards are a follow-up spec.
7. **IPv6 support**: This first spec covers IPv4 only. IPv6 forwarding, firewall rules, and DHCPv6 are future work.
8. **QoS / traffic shaping**: Bufferbloat mitigation (e.g., CAKE) is a follow-up spec.
9. **UPnP / NAT-PMP**: Automatic port forwarding for gaming consoles and applications is a follow-up spec.
10. **Hardware-configuration.nix generation**: This file must be generated on the physical device via `nixos-generate-config` and is never hand-edited.

## Design Considerations

No specific design requirements identified. This is a headless server/appliance with no desktop environment. The only UI element is the Pi-hole web admin dashboard, which uses its default interface.

## Repository Standards

- **Host structure**: Follow the self-contained host pattern used by `homelab` and `bee-gpu-server` -- the Vault's `default.nix` should be self-contained without importing shared `commonModules` (since it does not need desktop, gaming, or dev-tools modules)
- **Module organization**: Create host-specific modules under `hosts/protecli-vault/modules/` for networking, firewall, and services configuration (as suggested in the user's reference material)
- **Home-manager**: Include a minimal home-manager configuration inline (zsh, oh-my-posh) following the homelab pattern
- **Formatter**: `alejandra` (never nixfmt) -- `rebuild.sh` runs this automatically
- **User pattern**: Use `mainUser = "bee"` as a `let` binding, consistent with other hosts
- **Unstable packages**: Access via `pkgs.unstable.<package>` through the existing overlay (e.g., for Tailscale)
- **stateVersion**: Use `"25.05"` consistent with all other hosts
- **Function signatures**: Use `{config, pkgs, lib, ...}:` pattern in all modules
- **rebuild.sh**: Add `--protecli-vault` flag following the existing `--homelab`, `--pikvm`, `--bee-gpu-server` pattern with a `PROTECLI_VAULT_HOST` variable

## Technical Considerations

- **systemd-networkd over NetworkManager**: For a router/firewall appliance, `systemd-networkd` provides deterministic, declarative interface management. NetworkManager is designed for end-user machines with dynamic connectivity and is not appropriate for a device that must maintain a fixed network topology. This deviates from the desktop hosts' `modules/networking.nix` but aligns with best practices for NixOS routers (per 2025-2026 community guides).
- **nftables over iptables**: NixOS defaults to iptables but supports nftables via `networking.nftables.enable = true`. nftables is the modern successor with better syntax and performance. The NixOS firewall module (`networking.firewall`) will be disabled in favor of a complete custom nftables ruleset. This gives full control over filter and NAT rules without fighting the auto-generated `nixos-fw` table.
- **Predictable interface names**: The FW6C uses Intel i211 NICs. Interface names will follow the kernel's predictable naming scheme (e.g., `enp1s0`, `enp2s0`, etc.). The actual names must be determined on the physical hardware via `ip link` after NixOS installation. The spec will use placeholder names that must be replaced with actual interface names.
- **Bridge for LAN ports**: Four LAN ports will be bridged into a single `br-lan` interface using `systemd.network.netdevs`. This makes all LAN ports behave as a single network segment.
- **Docker for Pi-hole**: Pi-hole will run as a Docker container, consistent with how the homelab host runs containerized services (Jellyfin, Vaultwarden, etc.). Docker is already a pattern in this repository. Pi-hole's container handles both DHCP and DNS through its embedded FTL engine (a fork of dnsmasq), eliminating the need for a separate dnsmasq NixOS service. The Docker container must use `network_mode: host` or bind to `10.0.0.1` specifically so DHCP broadcasts work correctly on `br-lan`.
- **Unbound as native NixOS service**: Unbound will run as a native NixOS service (`services.unbound`) on `127.0.0.1:5335`. This is simpler and more declarative than running it in Docker. Pi-hole will be configured to use `127.0.0.1#5335` as its sole upstream DNS resolver. Unbound performs recursive resolution directly against root nameservers, providing full DNS privacy (no queries sent to Cloudflare/Google).
- **No separate dnsmasq service**: Since Pi-hole's FTL handles both DHCP and DNS, there is no need for a standalone dnsmasq NixOS service. This avoids port conflicts and reduces configuration complexity. Static DHCP leases are managed through Pi-hole's configuration (environment variables, config volume mounts, or the web admin UI).
- **Management port safety and remote rebuilds**: SSH is open on three paths: (1) the management port (`192.168.100.1`), (2) the LAN bridge (`10.0.0.1`), and (3) Tailscale. The management port's nftables accept rule is placed at the very top of the `input` chain, before any other rules. This means even if a bad configuration accidentally drops all `br-lan` or `tailscale0` input, the management port's SSH remains accessible. The `rebuild.sh` script defaults to using the management port IP but can use any reachable path. In practice, day-to-day rebuilds can go over LAN or Tailscale -- the management port is the emergency fallback.
- **Double-NAT initial topology**: The Vault's WAN port connects to the ISP router's LAN. The Vault gets a WAN IP via DHCP from the ISP router (e.g., `192.168.0.x`). The Vault then NATs its own LAN (`10.0.0.0/24`) behind this WAN IP. This creates double-NAT which is acceptable for initial development and testing.

## Security Considerations

- **SSH hardening**: `PermitRootLogin = "no"`, consider key-only authentication (disable password auth) following the pikvm pattern. Authorized keys for `bee` should be configured.
- **Management port isolation**: The management port is on a separate subnet (`192.168.100.0/24`) and only accepts SSH. It should be connected to a trusted device (e.g., your development machine) via a direct cable or a physically separate switch.
- **Default-deny firewall**: All nftables chains use `policy drop` -- only explicitly allowed traffic passes. This is the gold standard for firewall security.
- **No secrets in Nix files**: Tailscale auth keys, Pi-hole admin passwords, and any other credentials must not be committed to the repository. Use runtime secrets management (e.g., `agenix`, environment files, or manual post-deploy configuration).
- **Pi-hole admin password**: Set via `docker exec` or environment variable after deployment, not in the Nix configuration.
- **Firewall logging**: Dropped packets are logged for debugging and intrusion detection, but log rate limiting prevents log flooding attacks.

## Success Metrics

1. **Successful remote deployment**: `rebuild.sh --protecli-vault` completes without errors from the development machine
2. **LAN client connectivity**: A device connected to any LAN port gets a DHCP lease and can browse the internet through the Vault
3. **DNS ad blocking**: Pi-hole blocks requests to known ad domains for LAN clients
4. **Management port resilience**: SSH access via the management port works even when LAN-facing firewall rules are intentionally misconfigured during testing
5. **Tailscale connectivity**: The Vault is reachable via its Tailscale IP from other tailnet devices
6. **No existing network disruption**: The ISP router continues to serve the existing network; only devices physically connected to the Vault's LAN ports are affected

## Open Questions

1. **Actual interface names**: The predictable interface names (e.g., `enp1s0`, `enp2s0`) on the FW6C must be determined after NixOS installation via `ip link`. The spec uses placeholder names. Which physical port label (WAN, LAN, OPT1-OPT4) maps to which kernel interface name?
2. **Management port subnet choice**: `192.168.100.0/24` is suggested but any non-conflicting private subnet works. Should this be confirmed?
3. **Tailscale auth key management**: How should the Tailscale auth key be provisioned? The homelab uses `/var/lib/tailscale/authkey`. Should the same pattern be followed?
4. **Static DHCP leases**: Which devices need static leases? We know homelab (`10.0.0.150`) and pikvm (`10.0.0.175`), but are there others? MAC addresses will need to be collected.
5. **Pi-hole Docker networking mode**: Pi-hole needs to serve DHCP, which requires receiving broadcast traffic. This typically requires `network_mode: host` in Docker, which exposes all container ports on all host interfaces. An alternative is `macvlan` networking to give Pi-hole its own IP on `br-lan`. The trade-offs should be evaluated during implementation.
