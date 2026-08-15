# Task 04 Proofs - DHCP and DNS Services (Pi-hole Docker + Unbound NixOS Service)

## Task Summary

This task implements DNS and DHCP services for the Protecli Vault using Unbound (NixOS service) as the recursive DNS resolver and Pi-hole (Docker container) for DHCP, DNS caching, and ad blocking. Unbound runs on `127.0.0.1:5335`, Pi-hole forwards DNS queries to Unbound, and Pi-hole provides DHCP for the `10.0.0.50-254` range on the LAN.

## What This Task Proves

- Unbound is configured as a NixOS service listening on localhost port 5335 with DNSSEC validation.
- Pi-hole runs as a Docker container with host networking (required for DHCP broadcasts).
- Pi-hole is configured to use Unbound (`127.0.0.1#5335`) as its upstream DNS resolver.
- DHCP is enabled in Pi-hole with the correct range (`10.0.0.50-254`) and gateway (`10.0.0.1`).
- Persistent storage directories for Pi-hole are created via `systemd.tmpfiles.rules`.
- Service dependencies ensure Unbound starts before Pi-hole.
- `systemd-resolved` remains disabled (confirmed from Task 2.10) to avoid port 53 conflicts.
- `dnsutils` is already in system packages for DNS troubleshooting.

## Evidence Summary

- The `services.nix` module contains the complete Unbound and Pi-hole configuration.
- `alejandra --check .` passes with no formatting issues.
- `nix build --dry-run` evaluates successfully, including new Unbound and Docker service derivations.
- On-device verification (service status, DNS queries, DHCP leases) will be performed after deployment.

## Artifact: Complete services.nix module

**What it proves:** The services module implements Unbound with proper DNSSEC and security settings, Pi-hole with host networking and correct environment variables, persistent storage, and service dependencies.

**Why it matters:** This is the DNS/DHCP stack that will serve all LAN clients. The configuration ensures Pi-hole can receive DHCP broadcasts, Unbound provides recursive resolution, and services start in the correct order.

**Artifact path:** `hosts/protecli-vault/modules/services.nix`

**Result summary:** The module defines:
- **Unbound**: localhost-only listener on port 5335, 2 worker threads, DNSSEC enabled, identity/version hidden
- **Pi-hole**: Docker container with host networking, upstream DNS pointing to Unbound, DHCP active for `10.0.0.50-254` with gateway `10.0.0.1`, timezone set to America/Los_Angeles, empty web password (to be set manually), persistent volumes mounted
- **tmpfiles.rules**: Creates `/var/lib/pihole/etc-pihole` and `/var/lib/pihole/etc-dnsmasq.d` directories
- **Service dependencies**: `docker-pihole.service` requires and starts after `unbound.service`

Key configuration details:
```nix
services.unbound.settings.server = {
  interface = ["127.0.0.1"];
  port = 5335;
  access-control = ["127.0.0.0/8 allow"];
  num-threads = 2;
  hide-identity = true;
  hide-version = true;
};

virtualisation.oci-containers.containers.pihole = {
  image = "pihole/pihole:latest";
  extraOptions = ["--network=host"];
  environment.PIHOLE_DNS_ = "127.0.0.1#5335";
  environment.DHCP_START = "10.0.0.50";
  environment.DHCP_END = "10.0.0.254";
  environment.DHCP_ROUTER = "10.0.0.1";
};
```

## Artifact: Alejandra formatting check

**What it proves:** The services module follows the repository's formatting standard.

**Why it matters:** Consistent formatting is a repository guardrail per AGENTS.md.

**Command:**

```bash
alejandra .
```

**Result summary:** All 30 files checked, zero formatting changes needed.

```
Checking style in 30 files using 8 threads.
Congratulations! Your code complies with the Alejandra style.
```

## Artifact: Flake evaluation dry-run

**What it proves:** The protecli-vault configuration evaluates successfully with the new services module, including Unbound and Docker container derivations.

**Why it matters:** A successful dry-run confirms the service configuration is valid and properly integrated with the NixOS module system.

**Command:**

```bash
nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run
```

**Result summary:** The build plan includes 83 derivations. Notably, the output includes new service-specific derivations confirming both Unbound and Pi-hole are being processed:

```
/nix/store/...-unit-script-unbound-pre-start.drv
/nix/store/...-unit-script-docker-pihole-pre-stop.drv
```

No errors or warnings (aside from the expected "Git tree is dirty" warning).

## Artifact: systemd-resolved verification

**What it proves:** `systemd-resolved` is disabled to prevent port 53 conflicts with Pi-hole.

**Why it matters:** Pi-hole needs to bind to port 53 on the LAN bridge for DNS queries from clients. A running `systemd-resolved` would cause a conflict.

**Command:**

```bash
grep -rn "resolved" hosts/protecli-vault/
```

**Result summary:** The `networking.nix` module contains `services.resolved.enable = false;` with a comment explaining that DNS is handled by Pi-hole + Unbound. No conflicting settings exist.

```
hosts/protecli-vault/modules/networking.nix:36:   # ── Disable systemd-resolved (DNS handled by Pi-hole + Unbound) ────
hosts/protecli-vault/modules/networking.nix:37:   services.resolved.enable = false;
```

## Artifact: dnsutils package verification

**What it proves:** DNS troubleshooting tools (`dig`, `nslookup`) are available on the Vault.

**Why it matters:** These tools are essential for verifying DNS resolution during deployment and troubleshooting.

**Command:**

```bash
grep -n "dnsutils" hosts/protecli-vault/default.nix
```

**Result summary:** `dnsutils` is present in the `environment.systemPackages` list.

```
hosts/protecli-vault/default.nix:79:    dnsutils
```

## Reviewer Conclusion

The DNS and DHCP services are fully configured. Unbound provides recursive DNS resolution with DNSSEC validation on localhost port 5335. Pi-hole runs as a Docker container with host networking (required for DHCP), uses Unbound as its upstream resolver, serves DHCP for the `10.0.0.50-254` range with gateway `10.0.0.1`, and has persistent storage configured. Service dependencies ensure correct startup order. The configuration evaluates successfully and follows repository formatting standards.

On-device verification after deployment will confirm:
- Unbound is active and resolving queries
- Pi-hole container is running
- DHCP leases are being assigned to LAN clients
- DNS resolution works through the full Pi-hole → Unbound chain
- Ad blocking is functional
- Pi-hole web admin is accessible at `http://10.0.0.1/admin`
