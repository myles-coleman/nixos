# protecli-vault — Mullvad Exit Gateway Runbook

Operational runbook for the Mullvad-backed Tailscale exit gateway
(spec `05-spec-mullvad-tailscale-exit-gateway`).

## Architecture in one paragraph

LAN clients and tailnet clients that opt into the Vault as an exit node have
their internet traffic forwarded into a raw kernel WireGuard tunnel (`wg0`) to
a single pinned Mullvad server, using routing table `100`. A hard nftables kill
switch drops any forwarded client traffic that would leave the WAN (`enp1s0`),
and a uid-scoped output rule stops recursive Unbound DNS from leaking to the
WAN. The Vault's own host/system traffic deliberately stays on the WAN so the
box can always bootstrap and be managed. Tailscale runs with
`--netfilter-mode=off`; the Vault owns all forwarding and SNAT.

## Required secrets (sops)

Two secrets must exist in `secrets/secrets.yaml` before deploying:

| Secret | Purpose | Owner:Group | Mode |
| --- | --- | --- | --- |
| `mullvad_wg_private_key` | WireGuard private key for `wg0` | `systemd-network:systemd-network` | `0640` |
| `tailscale_auth_key` | Tailscale auth key for node registration | `root:root` | `0400` |

Add them with the sops age key available:

```bash
sops secrets/secrets.yaml
# add:
#   mullvad_wg_private_key: <base64 private key from `wg genkey`>
#   tailscale_auth_key: <tskey-auth-...>
```

### One-time Mullvad key setup

1. Generate a keypair client-side:
   ```bash
   umask 077
   wg genkey | tee private.key | wg pubkey > public.key
   ```
2. Register `public.key` on the Mullvad account page (WireGuard configuration
   generator) and copy the assigned tunnel address (`10.64.x.x/32`), the server
   endpoint IP, and the server public key.
3. Put the private key into `mullvad_wg_private_key` (above).
4. Fill the three placeholders in `hosts/protecli-vault/modules/mullvad.nix`:
   `mullvadEndpoint`, `mullvadTunnelAddress`, `mullvadPeerPublicKey`.
5. Delete the local key files once the secret is stored.

## Changing Mullvad location or port

Edit `mullvadServerIp` in `hosts/protecli-vault/modules/mullvad.nix` and rebuild.
To use a different UDP port, edit `mullvadPort` (it must be a port the chosen
relay accepts; `51820` is the generator default, but `53`, `1234`, `443`, and
`5001` are also commonly available). The WireGuard key and tunnel address work
across all Mullvad servers, so no new key registration is required.

Changing the port can bypass a network that blocks a specific UDP port, but it
does not hide that the traffic is WireGuard — that requires Mullvad's app-only
obfuscation, which this kernel-WireGuard design does not use.

If you change servers specifically to avoid linking activity across locations,
rotate the WireGuard key as well (see Operational notes).

## Deploy

```bash
./rebuild.sh --protecli-vault --dry-run   # evaluate/build only
./rebuild.sh --protecli-vault             # build locally, deploy to the Vault
```

The Vault is targeted over Tailscale (`bee@100.112.185.27`). The dedicated
break-glass management port `enp6s0` (`192.168.100.1`) is unconditionally allowed
by the firewall and should be used if a change breaks LAN/Tailscale access.

## Verification / leak test

Run on the Vault unless noted. Expected results are in brackets.

### 1. Tunnel and routing

```bash
sudo ip -d link show wg0                 # [wireguard, mtu 1420]
sudo wg show wg0                         # [peer endpoint, allowed ips 0.0.0.0/0, recent handshake]
sudo ip route show table 100             # [default dev wg0 metric 0; blackhole default metric 1000]
sudo ip rule show                        # [3 scoped rules: from 192.168.1.0/24 iif br-lan; iif tailscale0; uidrange <unbound>]
```

Client traffic must tunnel while host traffic does not:

```bash
sudo ip route get 8.8.8.8 from 192.168.1.50 iif br-lan   # [via wg0]
sudo ip route get 8.8.8.8                                 # [via enp1s0, NOT wg0]
```

### 2. DNS through the tunnel

```bash
dig +short google.com @127.0.0.1 -p 5335   # [valid answer, wg0 up]
```

### 3. Hard kill switch (no WAN leak)

On the Vault:

```bash
sudo ip link set wg0 down
sudo ip route get 8.8.8.8 from 192.168.1.50 iif br-lan   # [matches blackhole]
sudo tcpdump -ni enp1s0 port 53                          # [no Unbound DNS leaving WAN]
```

From a LAN client (with `wg0` still down):

```bash
curl --max-time 5 https://ifconfig.me    # [fails; no WAN fallback]
```

Restore:

```bash
sudo ip link set wg0 up
```

### 4. Ruleset snapshot

```bash
sudo nft list ruleset | tee /tmp/nft-$(date +%F).ruleset
# [shows wg0 masquerade, HARD KILL SWITCH drops, skuid unbound drop, MSS clamps, ipv6 drop]
```

### 5. Tailscale exit node / subnet router

On the Vault:

```bash
tailscale debug prefs                    # [NetfilterMode: 0]
tailscale status                         # [Vault offers exit node + 192.168.1.0/24]
sudo nft list ruleset | grep ts-         # [nothing, including after a cold reboot]
```

On a remote tailnet client:

```bash
tailscale set --exit-node=<vault>
curl https://ifconfig.me                 # [a Mullvad exit IP]
ping 192.168.1.1                         # [subnet routing works]
nslookup google.com                      # [resolved via Vault/Pi-hole]
nslookup doubleclick.net                 # [blocked]
tailscale set --exit-node=               # (to stop using the exit node)
```

### 6. Watchdog

```bash
sudo journalctl -u wg0-watchdog          # [emerg alert if the handshake is stale]
```

### 7. Secret hygiene

```bash
git grep -n "tskey-\|REPLACE_WITH\|BEGIN PRIVATE"   # [no real secrets committed]
```

## Manual Tailscale admin steps (one-time)

1. Approve the Vault as an exit node.
2. Approve the advertised subnet route `192.168.1.0/24`.
3. Tag the node and disable key expiry.
4. Set the tailnet global nameserver to Pi-hole's tailnet IP, with
   **Override DNS servers** and **Use with exit node** both enabled.
5. Per-device opt-in: `tailscale set --exit-node=<vault>` (and
   `tailscale set --exit-node=` to opt out). There is no MDM/system-policy
   enforcement.

## Watchdog behavior

A timer runs every 60 seconds. If `wg0` has had no handshake for more than
300 seconds, the watchdog logs at `daemon.emerg` and optionally runs a
notification command. It never fails open and never rolls back a generation.

To add a notification hook, set `services.mullvadWatchdog.notifyCommand` (for
example an ntfy `curl` call) in `hosts/protecli-vault/default.nix`.

## Manual rollback procedure

Automatic rollback is intentionally not implemented: a rollback to a generation
that predates the kill switch could remove the tunnel and silently restore
plain-WAN egress. To roll back manually:

1. Reach the Vault via the `enp6s0` management port (`192.168.100.1`) or the
   tailnet control plane (which stays reachable even when client egress is
   hard-killed).
2. Inspect generations: `nixos-rebuild list-generations`.
3. Switch to the previous generation and reboot, or revert the offending
   commit and run `./rebuild.sh --protecli-vault`.
4. Re-run the verification / leak test above before considering the rollback
   complete.

## Operational notes

- **Mullvad location change**: one-line edit of `mullvadEndpoint` plus rebuild.
- **WireGuard key rotation**: Mullvad's exit-IP assignment can link sessions
  across server changes; rotate the key (log out/in on the account, or generate
  and re-register a new key) when changing locations for privacy reasons.
- **Device limit**: the Mullvad account allows a limited number of devices
  (currently 5); all tailnet identities that exit through the Vault share this
  account, so keep tailnet grants tight.
- **DNS fallback**: if Mullvad anti-abuse limits interfere with recursive
  Unbound on port 53, the reversible fallback is to point Unbound upstream at
  `10.64.0.1` (Mullvad's in-tunnel resolver) and adjust the policy rules so
  that traffic takes table 100. This is a manual, reversible change.
- **App-only features**: DAITA, multihop, quantum-resistant tunnels, and
  obfuscation are implemented in Mullvad's userspace client and are not
  available on this kernel-WireGuard design.
