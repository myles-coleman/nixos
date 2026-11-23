# protecli-vault — segmented edge router runbook

Operational runbook for the Vault as the sole home edge: four LAN segments, a
DHCP/DNS plane, the Tailscale exit node + subnet router, and the Mullvad tunnel
that exists only for tailnet exit-node clients.

Specs: `29-spec-protecli-vault-lan-segmentation` (segments, DNS, tailnet) and
`05-spec-mullvad-tailscale-exit-gateway` (exit node, table 100, kill switch).

## Architecture in one paragraph

The Vault is the only router. `enp1s0` is a DHCP WAN from the Hitron CODA56
modem-only bridge (Xfinity/Comcast). The LAN is split into four Linux bridges,
each with its own subnet, gateway and DHCP scope: `br-homelab` `10.0.0.0/24`
(estate switch: homelab, k3s, kube-vip, PiKVM, Traefik), `br-gaming`
`10.20.0.0/24`, `br-ai` `10.30.0.0/24`, `br-wifi` `10.50.0.0/24`. Every segment
egresses **direct to the WAN**; inter-segment traffic is denied by default with
a small allow matrix. The management port `enp6s0` is `192.168.200.1/24`, is
never advertised to the tailnet, and is the break-glass path. DNS is Pi-hole →
recursive Unbound out the WAN. `wg0` (a single pinned Mullvad relay) carries
**only** tailnet exit-node clients (`tag:media-egress`: qBittorrent, Prowlarr),
which fail closed when the tunnel is down.

## Segment matrix

The matrix lives in `hosts/protecli-vault/modules/segments.nix` and is the only
place a subnet, gateway, pool or port is written. networkd netdevs/.network
files, DHCP scopes, policy-routing rules, nftables rules and the Tailscale
advertise list are generated from it.

| Segment | Bridge | Port (PCI path) | Subnet | Gateway | DHCP pool |
| --- | --- | --- | --- | --- | --- |
| homelab | `br-homelab` | `enp4s0` (`04:00.0`) | `10.0.0.0/24` | `10.0.0.1` | `.60-.89` |
| gaming | `br-gaming` | `enp5s0` (`05:00.0`) | `10.20.0.0/24` | `10.20.0.1` | `.20-.99` |
| ai | `br-ai` | `enp3s0` (`03:00.0`) | `10.30.0.0/24` | `10.30.0.1` | `.20-.99` |
| wifi | `br-wifi` | `wlp7s0` (hostapd) | `10.50.0.0/24` | `10.50.0.1` | `.20-.199` |
| mgmt | — | `enp6s0` (`06:00.0`) | `192.168.200.0/24` | `192.168.200.1` | none (static) |

`enp2s0` is the spare port and is deliberately inert (no address, no DHCP, no
link-local). Fixed addresses: gaming PC `10.20.0.10` (reserved),
`bee-gpu-server` `10.30.0.10` (static on the host + reserved).

## Allow matrix (forward chain)

Default deny. Everything else is dropped and logged.

| From | To | Port |
| --- | --- | --- |
| any segment | WAN | any |
| any segment | tailnet | any (subnet-routing replies/requests) |
| tailnet | any segment | any (subnet routing) |
| tailnet | `wg0` | any (exit-node clients) |
| gaming | AI `10.30.0.10` | tcp/8080 |
| mgmt | anywhere | any (break-glass) |
| any segment / tailnet | mgmt | **denied** |

Each segment port is anti-spoofed: a packet arriving on a bridge with a source
outside that bridge's subnet is logged and dropped.

## Required secrets (sops)

Two secrets must exist before deploying:

| Secret | Purpose | Owner:Group | Mode |
| --- | --- | --- | --- |
| `mullvad_wg_private_key` | WireGuard private key for `wg0` | `systemd-network:systemd-network` | `0640` |
| `tailscale_auth_key` | Tailscale auth key for node registration | `root:root` | `0400` |

The AP password is `ap_password` in `secrets/hosts/protecli-vault.yaml`
(`sops.secrets.ap_password`). Never print any of them; never put them in the
Nix store.

## Deploy

This host is not in the local `rebuild.sh` allowlist (`bee-pc`, `bee-gpd`).
Deploy from CI with a `workflow_dispatch` run of the Deploy workflow
(`hosts: protecli-vault`), or from a machine that can reach it:

```bash
nixos-rebuild switch --flake .#protecli-vault --target-host bee@10.50.0.1 --use-remote-sudo
# or, once the tailnet route is approved:
nix run .#deploy -- .#protecli-vault --skip-checks -- -L
```

**The Vault is headless: no console, no KVM.** Any change to bridging, the WiFi
AP, or the firewall must be deployed from a laptop plugged into the management
port `enp6s0` with `192.168.200.2/24` (no gateway, no DNS — keep the hotspot for
internet):

```bash
ssh bee@192.168.200.1
```

Never deploy a network-shape change (bridges, `br-wifi`/hostapd, `br-lan`
retirement) over the WiFi or LAN link it is reconfiguring. Keep the previous
generation.

Build-only check that never touches the Vault:

```bash
nix build .#packages.x86_64-linux.protecli-vault
```

## Verification

Run on the Vault unless noted. Expected results in brackets.

### 1. WAN, bridges, policy routing

```bash
ip -br addr                                  # [enp1s0 DHCP + 192.168.100.2/24; one address per bridge]
ip -br link                                  # [br-homelab, br-gaming, br-ai, br-wifi UP]
ip link show master br-homelab               # [enp4s0]
ip link show master br-gaming                # [enp5s0]
ip link show master br-ai                    # [enp3s0]
ip link show master br-wifi                  # [wlp7s0]
ip -br addr show enp2s0                      # [no address: spare port is inert]
ip rule                                      # [to 10.0.0.0/24, 10.20.0.0/24, 10.30.0.0/24,
                                             #  10.50.0.0/24, 192.168.200.0/24 lookup main,
                                             #  then iif tailscale0 lookup 100]
ip route show table 100                      # [default dev wg0; 100.64.0.0/10 dev tailscale0;
                                             #  blackhole default metric 1000]
ip route get 8.8.8.8 from 10.0.0.50 iif br-homelab   # [via enp1s0, NOT wg0]
```

### 2. DHCP authority and DNS

```bash
networkctl status br-gaming                  # [DHCPServer active, leases]
ss -lunp | grep ':67'                        # [nothing: Pi-hole DHCP is off]
dig +short example.com @10.0.0.1             # [an address]
dig +short example.com @127.0.0.1 -p 5335    # [an address: recursive Unbound]
sudo journalctl -u unbound | tail            # [recursion, not a forwarder]
```

DNS must keep working with the tunnel down:

```bash
sudo ip link set wg0 down
dig +short example.com @10.0.0.1             # [still resolves]
sudo ip link set wg0 up
```

### 3. Firewall boundary and the media-egress path

```bash
sudo nft list ruleset | tee /tmp/nft-$(date +%F).ruleset
# [segment_prefixes set; per-bridge anti-spoof drops; mgmt deny; gaming->AI tcp/8080;
#  tailscale0->wg0 + wg0->tailscale0; bogon egress; exactly one
#  `iifname "tailscale0" oifname "enp1s0" drop`]
```

Inter-segment probes (expected: homelab unreachable from gaming, AI port
reachable):

```bash
# from the gaming PC
ping -c1 <homelab-host>                      # [fails: default deny]
# 10.30.0.10:8080                             # [connects: allow matrix]
```

Anti-spoof: from a segment, add a foreign source address and try to reach the
WAN; the packet is dropped with `anti-spoof <bridge>:` in the journal.

### 4. WiFi

```bash
iw dev wlp7s0 info                           # [type AP, ssid beans-test, channel 149, master br-wifi]
systemctl is-active hostapd                  # [active]
networkctl status br-wifi                    # [DHCPServer active; a 10.50.0.x lease]
```

### 5. Tailscale exit node / subnet router

```bash
tailscale debug prefs                        # [NetfilterMode 0; AdvertiseRoutes = 0.0.0.0/0,
                                             #  10.0.0.0/24, 10.20.0.0/24, 10.30.0.0/24, 10.50.0.0/24]
tailscale status                             # [offers exit node; four subnet routes]
sudo nft list ruleset | grep ts-             # [nothing, including after a cold reboot]
```

On a remote tailnet client:

```bash
tailscale set --exit-node=<vault>
curl https://ifconfig.me                     # [a Mullvad exit IP]
ping 10.50.0.1                               # [subnet routing works, once approved]
tailscale set --exit-node=                   # (stop using the exit node)
```

Media egress must fail closed:

```bash
# with wg0 down, from qBittorrent/Prowlarr: downloads stop, not fall back to the WAN
```

### 6. Watchdog

```bash
sudo journalctl -u wg0-watchdog              # [emerg alert if the handshake is stale]
```

### 7. Secret hygiene

```bash
git grep -n "tskey-\|REPLACE_WITH\|BEGIN PRIVATE"   # [no real secrets committed]
```

## Manual Tailscale admin steps (one-time, per prefix)

1. Approve the Vault as an exit node.
2. Approve each advertised subnet route: `10.0.0.0/24`, `10.20.0.0/24`,
   `10.30.0.0/24`, `10.50.0.0/24`. `192.168.200.0/24` is never advertised.
3. Tag the node and disable key expiry.
4. Set the tailnet global nameserver to Pi-hole's tailnet IP, with
   **Override DNS servers** and **Use with exit node** both enabled.
5. The policy itself is `~/homelab-terraform/modules/tailscale/tailnet.hujson`
   (OpenTofu `tailscale_acl`), not a file in this repo.
6. Per-device opt-in: `tailscale set --exit-node=<vault>` (and
   `tailscale set --exit-node=` to opt out).

## Rollback

1. Reach the Vault over `enp6s0` (`192.168.200.1`) — the management port is
   unconditionally accepted. The tailnet control plane also stays reachable
   unless the box is down.
2. `nixos-rebuild list-generations`; `sudo nixos-rebuild switch --rollback`
   restores the previous generation.
3. If the network shape is wrong, the previous generation restores the previous
   bridges/addresses; the management link is unaffected because `enp6s0` is
   configured by every generation.
4. Re-run the verification set before considering the rollback complete.
5. Deep fallback: GRUB generation 50 (NixOS 25.05, kernel 6.12).

Automatic rollback is intentionally not implemented: a rollback to a generation
that predates the kill switch could restore plain-WAN egress for exit-node
clients.

## Operational notes

- **WAN**: DHCP from the CODA56 (Xfinity). The old static `10.0.0.227/24` is
  history. `192.168.100.2/24` is an alias on `enp1s0` for the modem GUI at
  `https://192.168.100.1` (source-restricted, HTTPS only).
- **DNS**: Unbound resolves by full recursion from the root servers out the WAN
  (spec 29, Unit 1). Pi-hole's only upstream is `127.0.0.1#5335`. The old
  forwarder `10.64.0.1` and its table-100 policy rule are gone; if recursion
  ever breaks, restore the `forward-zone` and the `{ User = "unbound"; Table =
  100; }` rule. Accepted trade-off: the ISP sees the queries. DNSSEC validation
  stays on, so a hijacked answer is SERVFAIL.
- **DHCP**: systemd-networkd is the only DHCP server, one scope per bridge.
  Pi-hole `dhcp.active=false` is explicit because Pi-hole v6 persists
  `FTLCONF_*` values into `pihole.toml`; removing the env var does not revert
  them. Same reason `FTLCONF_dns_interface=""` is explicit.
- **Policy routing**: each bridge installs `to <subnet> lookup main`; the WAN
  network installs `iif tailscale0 lookup 100`. Order matters: tailnet-to-LAN
  must resolve through `main`, while internet-bound tailnet traffic falls into
  table 100 (`wg0` + blackhole). `ManageForeignRoutingPolicyRules=no` keeps
  networkd from deleting Tailscale's own 5210-5270 fwmark rules and table 52.
- **Bridge netfilter**: `br_netfilter` is forced off
  (`bridge-netfilter-off.service`) because Docker loads it and it would feed
  each bridge's L2 frames to the routed `forward` chain (policy drop). Each
  bridge is one flat L2 domain; the L3 rules cover everything routed.
- **WiFi**: QCA6174A-5, 5 GHz only, `beans-test`, WPA3-SAE, channel 149, 80 MHz
  (`ap_isolate=1`). 6.18 needs `cfg80211.ieee80211_regdom=US` plus
  `ath10k-regdomain.service` before hostapd starts (the phy registers under the
  world domain otherwise and 5 GHz becomes NO-IR). 2.4 GHz-only clients (rpi3)
  need wire.
- **Tailscale flags**: `extraUpFlags` only apply on a fresh login; the same
  flags are re-applied on every boot via `extraSetFlags`. The advertise list is
  generated from the segment matrix, so changing a subnet changes the routes.
- **Mullvad**: one pinned relay, one device. Changing `mullvadEndpoint` is a
  one-line edit; rotate the key when changing locations for privacy.
  `tailscaled` runs `--netfilter-mode=off`: the Vault owns all forwarding.
- **App-only features**: DAITA, multihop, quantum-resistant tunnels and
  obfuscation are userspace-client features and are not available here.
