# 01-spec-secure-dns-vpn-gateway.md

## Introduction/Overview

This specification details the implementation of a "High-Performance Secure DNS & VPN Gateway" on the `protecli-vault` host. The goal is to transform the existing router into a centralized security hub that provides ad-blocking, recursive DNS, and total privacy for both local LAN devices and remote Tailscale clients by leveraging Mullvad VPN and Tailscale.

## Goals

- Implement a robust Mullvad WireGuard tunnel as the primary outbound routing path for all internet-bound traffic.
- Configure the host as a Tailscale Exit Node and Subnet Router to provide secure remote access.
- Ensure consistent DNS resolution across the entire network (Local + Remote) by routing all requests through the Pi-hole/Unbound stack.
- Maintain high-performance throughput by leveraging hardware-accelerated encryption (AES-NI).

## User Stories

- **As a local user**, I want my internet traffic to be automatically routed through a Mullvad VPN tunnel so that my browsing remains private and secure from my ISP.
- **As a remote user**, I want to connect via Tailscale and use my home gateway as an "Exit Node" so that I can browse the internet from untrusted networks as if I were at home.
- **As a remote user**, I want to access my local network devices (e.g., my home lab) via Tailscale so that I can manage them securely from anywhere.
- **As a network administrator**, I want all devices, whether local or remote, to benefit from Pi-hole ad-blocking so that my entire digital footprint is cleaner and more private.

## Demoable Units of Work

### [Unit 1]: Mullvad Outbound Tunnel Implementation

**Purpose:** Establishes the primary privacy layer for the host and local network.

**Functional Requirements:**
- The system shall establish a WireGuard tunnel to Mullvad.
- The system shall implement policy-based routing to direct all traffic from `br-lan` and `wifi` through the Mullvad interface instead of the `wan` interface.
- The system shall implement a "kill-switch" mechanism via `nftables` to prevent traffic leaks if the Mullvad tunnel fails.

**Proof Artifacts:**
- `CLI: curl ifconfig.me` on a local device demonstrates that the returned IP address belongs to the Mullvad VPN provider.
- `CLI: traceroute 8.8.8.8` on a local device demonstrates that the first hop after the gateway is the Mullvad WireGuard peer.

### [Unit 2]: Tailscale Exit Node & Subnet Routing

**Purpose:** Enables secure remote access to the home network and internet.

**Functional Requirements:**
- The system shall configure Tailscale as a Subnet Router for the `192.168.1.0/24` network.
- The system shall configure Tailscale as an Exit Node.
- The system shall update `nftables` to allow Tailscale traffic to be routed through the Mullvad tunnel.

**Proof Artifacts:**
- `CLI: curl ifconfig.me` from a remote Tailscale client demonstrates that the internet traffic exits via the host's Mullvad IP.
- `CLI: ping <local_ip>` from a remote Tailscale client demonstrates successful subnet routing to the local LAN.

### [Unit 3]: Unified DNS via Tailscale MagicDNS

**Purpose:** Ensures consistent ad-blocking and privacy for remote clients.

**Functional Requirements:**
- The system shall configure Tailscale (via MagicDNS or Global Nameservers) to use the Pi-hole container (192.168.1.1) as the primary DNS resolver.
- The system shall ensure the Pi-hole container remains reachable from the Tailscale interface.

**Proof Artifacts:**
- `CLI: nslookup google.com` from a remote Tailscale client demonstrates that the response comes from the Pi-hole IP (192.168.1.1).
- `CLI: nslookup ads.example.com` (an ad domain) from a remote client demonstrates successful ad-blocking by Pi-hole.

## Non-Goals (Out of Scope)

1. **[Hardware Change]**: No new physical network interfaces or hardware components will be added.
2. **[New DNS Engine]**: This spec does not replace Pi-hole/Unbound but rather integrates them into the remote access flow.
3. **[Full Firewall Migration]**: We are enhancing the existing `nftables` ruleset, not replacing the entire firewall architecture.

## Design Considerations

- **Interface Management**: Use `systemd-networkd` to manage the WireGuard and Tailscale interfaces.
- **Routing Logic**: Implement Policy-Based Routing (PBR) using `nftables` and `ip rule` to distinguish between local traffic and host-only traffic.
- **No UI**: The implementation will be entirely configuration-driven via NixOS.

## Repository Standards

- **Networking**: Follow the established `systemd-networkd` and `nftables` patterns used in `hosts/protecli-vault/`.
- **Containerization**: Continue using `virtualisation.oci-containers` for Pi-hole.
- **NixOS Configuration**: All changes must be modularized within the `protecli-vault` host configuration.

## Technical Considerations

- **WireGuard Performance**: Use `pkgs.wireguard-tools` and ensure kernel-level WireGuard is utilized for maximum throughput.
- **Tailscale Integration**: Utilize NixOS `services.tailscale` with `options = [ "accept-routes" "advertise-exit-node" "advertise-routes=192.168.1.0/24" ]`.
- **Mullvad Routing**: To achieve the "High-Performance" requirement, we will use `nftables` to mark packets from the LAN and route them through a specific routing table that uses the WireGuard interface as the default gateway.

## Security Considerations

- **Kill-Switch**: Implement an `nftables` rule that drops all traffic from `br-lan` if the Mullvad interface is down.
- **Secret Management**: Mullvad WireGuard private keys must be handled securely (e.g., via a secret file or environment variable, not hardcoded in the Nix config).
- **Management Access**: Ensure the `mgmt` interface remains isolated and accessible even when the VPN/Tailscale rules are active.

## Success Metrics

1. **Outbound Privacy**: 100% of LAN and Tailscale Exit Node traffic is routed through Mullvad.
2. **DNS Consistency**: 100% of remote Tailscale queries are successfully resolved by the local Pi-hole.
3. **Stability**: The gateway maintains uptime and connectivity during VPN re-connections.

## Open Questions

1. Do you have a Mullvad WireGuard configuration file (`.conf`) ready, or should I include the process of generating it?
2. For the Mullvad "kill-switch", should we prioritize complete isolation (no internet if VPN is down) or allow fallback to ISP (less secure)?
