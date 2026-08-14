# 02 Questions Round 1 - Protecli Vault Firewall

Please answer each question below (select one or more options, or add your own notes). Feel free to add additional context under any question.

## 1. Scope for This First Spec

Your reference material wisely recommends an incremental approach: "Get basic routing working -> Add VLANs -> Add NAT -> Add WireGuard -> Add Suricata." Should this first spec cover only the foundational layer, or do you want more included?

- [X] (A) Foundation only: host in flake + basic WAN/LAN routing + NAT + nftables firewall + DHCP server + DNS forwarding + SSH management + Tailscale
- [ ] (B) Foundation + VLANs (network segmentation for different device types)
- [ ] (C) Foundation + VLANs + WireGuard (remote access VPN)
- [ ] (D) Everything (routing, VLANs, NAT, WireGuard, Suricata, monitoring) in one spec
- [ ] (E) Other (describe)

**Recommended answer(s):** [(A)]

**Why these are recommended:**

- `(A)` follows your own "start simple" guidance and produces the smallest demoable slice: a working router you can actually use before layering complexity.
- `(A)` keeps the spec focused enough that each functional requirement is clear and testable.
- `(D)` would create an unmanageably large spec with too many interdependencies, making debugging much harder when something doesn't work.
- VLANs, WireGuard, Suricata, and monitoring are each natural follow-up specs once the foundation is validated.

## 2. NixOS Installation Status

Is NixOS already installed on the Protecli Vault, or does the spec need to cover initial OS installation?

- [ ] (A) NixOS is already installed and booting -- just need the flake configuration
- [ ] (B) NixOS is NOT installed yet -- include installation steps in the spec
- [X] (C) I plan to install NixOS separately before implementing the spec (spec should just cover configuration)
- [ ] (D) Other (describe)

**Recommended answer(s):** [(C)]

**Why these are recommended:**

- NixOS installation is a one-time physical task (USB boot, partition, nixos-install) that doesn't belong in a declarative configuration spec.
- `(C)` keeps the spec focused on the repeatable, version-controlled configuration.
- If you choose `(B)`, we can add a brief installation reference section, but the core spec should focus on configuration.

## 3. Port Assignment (6 Ports Available)

The FW6C has 6 Intel i211 Gigabit Ethernet ports labeled WAN, LAN, OPT1, OPT2, OPT3, OPT4. Your reference material mentions a "management port" strategy. How do you want to assign these ports?

- [X] (A) 1 WAN + 4 LAN (bridged) + 1 Management (dedicated SSH-only port) = 6 ports used
- [ ] (B) 1 WAN + 5 LAN (bridged, including management access via LAN) = 6 ports used
- [ ] (C) 1 WAN + 3 LAN (bridged) + 1 Management + 1 unused/reserved = 6 ports used
- [ ] (D) Other (describe your preferred port assignment)

**Current best-practice context:** The "dedicated management port" strategy is a common safety pattern for network appliances. It ensures SSH access survives firewall misconfigurations. However, with NixOS's `nixos-rebuild test` (which auto-rolls back), the risk of permanent lockout is lower than with traditional firewall OSes.

**Recommended answer(s):** [(A)]

**Why these are recommended:**

- `(A)` follows your own "Safety First" guidance with a dedicated management port while maximizing LAN port availability.
- `(B)` is simpler but loses the safety net of a guaranteed SSH access path. With `nixos-rebuild test` as a safety mechanism, this could be acceptable.
- The management port can always be repurposed later once you're confident in the configuration.

## 4. Network Topology and IP Scheme

What IP addressing scheme do you want for this router?

- [X] (A) Keep existing scheme: router at 10.0.0.1, existing devices keep their current IPs (homelab 10.0.0.150, pikvm 10.0.0.175, etc.), DHCP range for dynamic clients
- [ ] (B) New subnet scheme: router on a different subnet (e.g., 192.168.1.0/24) with the existing 10.0.0.0/24 on a separate segment
- [ ] (C) Use 10.0.0.1/24 for LAN with management port on a separate subnet (e.g., 192.168.100.0/24)
- [ ] (D) Other (describe your preferred IP scheme)

**Recommended answer(s):** [(A), (C)]

**Why these are recommended:**

- `(A)` is simplest and avoids breaking existing device configurations. Your homelab, pikvm, and other devices are already on 10.0.0.x.
- `(C)` adds the management port on a separate subnet, which aligns with the safety port strategy. The management port would be on a completely different network than the LAN.
- `(B)` would require reconfiguring all existing devices, which is unnecessary disruption.

## 5. DHCP Transition

Is something currently serving DHCP on your network (e.g., your ISP router)? Will this Vault replace it?

- [ ] (A) Yes, my ISP router currently serves DHCP -- the Vault will fully replace it as the network gateway and DHCP server
- [X] (B) Yes, my ISP router serves DHCP -- the Vault will sit behind it (double-NAT) initially, and I'll switch to bridge/passthrough mode on the ISP router later
- [ ] (C) Yes, another device serves DHCP -- the Vault will replace that device
- [ ] (D) I want the Vault to be the DHCP server from day one, replacing whatever currently serves DHCP
- [ ] (E) Other (describe)

**Recommended answer(s):** [(B)]

**Why these are recommended:**

- `(B)` allows you to develop and test the Vault configuration without disrupting your existing network. You can run the Vault's WAN port off your ISP router's LAN, with the Vault serving its own LAN subnet.
- Once the Vault is stable and validated, you can switch the ISP router to bridge/passthrough mode to eliminate double-NAT.
- `(A)` and `(D)` are the end goal but are riskier for initial deployment -- if something goes wrong, your whole network goes down.

## 6. DNS Strategy

What DNS approach do you want for the LAN?

- [ ] (A) Simple DNS forwarding: dnsmasq forwards to upstream DNS (Cloudflare 1.1.1.1 / Google 8.8.8.8), no ad blocking
- [ ] (B) DNS forwarding with ad blocking: use Blocky or AdGuard Home for DNS-level ad blocking
- [ ] (C) DNS forwarding with local domain resolution: dnsmasq with custom local domain entries (e.g., homelab.lan, pikvm.lan)
- [ ] (D) Both ad blocking and local domain resolution
- [X] (E) Other (describe) - DNS forwarding with pihole + unbound as a recursive dns 

**Recommended answer(s):** [(C)]

**Why these are recommended:**

- `(C)` gives you DNS forwarding plus the ability to resolve local hostnames like `homelab.lan` -> `10.0.0.150`, which is immediately useful.
- Ad blocking (`(B)`, `(D)`) is a nice-to-have that can be added in a follow-up spec without complicating the foundation.
- dnsmasq handles both DHCP and DNS in a single service, which simplifies the configuration.

## 7. Remote Deployment Strategy

How will you deploy NixOS configurations to the Vault?

- [X] (A) Same as homelab/pikvm: `rebuild.sh --protecli-vault` deploying via SSH (`nixos-rebuild switch --flake .#protecli-vault --target-host bee@<ip> --use-remote-sudo`)
- [ ] (B) Locally on the Vault itself (clone the repo and run `nixos-rebuild switch` there)
- [ ] (C) Both -- remote deploy for normal use, local as fallback
- [ ] (D) Other (describe)

**Recommended answer(s):** [(A)]

**Why these are recommended:**

- `(A)` follows the established pattern used by homelab and pikvm -- centralized management from your development machine.
- This keeps the Vault lightweight (no need for a full dev environment on it).
- The management port guarantees SSH connectivity even during firewall rule changes.

## 8. Tailscale Role

What role should Tailscale play on the Vault?

- [ ] (A) Basic Tailscale client: remote access to the Vault itself via Tailscale
- [ ] (B) Tailscale subnet router: advertise the LAN subnet so you can access LAN devices remotely via Tailscale
- [ ] (C) Tailscale exit node: route all remote traffic through your home network
- [ ] (D) Both subnet router and exit node (similar to your pikvm setup)
- [ ] (E) No Tailscale on the Vault (already handled by pikvm)
- [X] (F) Other (describe) - Tailscale exit node with mullvad vpn. I want all network traffic and routed through this machine as an exit node. and i want all network traffic routed through mullvad (this may need to be an entire spec on its own)

**Recommended answer(s):** [(A)]

**Why these are recommended:**

- `(A)` gives you remote SSH access to the Vault for management, which is the minimum needed.
- Your pikvm already serves as a Tailscale exit node and subnet router (`useRoutingFeatures = "both"`, advertises `10.0.0.0/24`). Adding the same on the Vault would create a conflict.
- If you later retire the pikvm's routing role, you can upgrade the Vault's Tailscale configuration in a follow-up.
- `(E)` is also reasonable since the pikvm handles it, but having Tailscale on the Vault itself ensures you can always reach it remotely.

## 9. Existing Network Integration

When the Vault is deployed, how should it relate to your existing devices?

- [ ] (A) The Vault becomes the primary gateway for all LAN devices (homelab, pikvm, etc. point their default gateway to the Vault)
- [ ] (B) The Vault only routes for devices connected to its LAN ports -- existing devices stay on the ISP router
- [X] (C) Gradual migration: start with (B), then move devices to (A) as confidence grows
- [ ] (D) Other (describe)

**Recommended answer(s):** [(C)]

**Why these are recommended:**

- `(C)` is the safest approach -- you can test the Vault's routing with a single device first before migrating everything.
- `(A)` is the end goal but doing it immediately risks disrupting your homelab services if something goes wrong.
- `(B)` alone doesn't exercise the Vault as a real router for your network.
