# 02-tasks-protecli-vault-firewall.md

## Relevant Files

| File | Why It Is Relevant |
| --- | --- |
| `flake.nix` | Add `protecli-vault` to `nixosConfigurations` following the homelab/bee-gpu-server self-contained pattern |
| `rebuild.sh` | Add `--protecli-vault` flag with `PROTECLI_VAULT_HOST` variable for remote deployment |
| `hosts/protecli-vault/default.nix` | Main host configuration: base system, imports, boot, hostname, user, SSH, Tailscale, Docker, packages |
| `hosts/protecli-vault/hardware-configuration.nix` | Auto-generated on the physical device via `nixos-generate-config` -- placeholder until device is available |
| `hosts/protecli-vault/home/default.nix` | Minimal home-manager config: zsh, oh-my-posh, rebuild alias (mirrors homelab pattern) |
| `hosts/protecli-vault/modules/networking.nix` | systemd-networkd configuration: WAN, br-lan bridge, management port, IP forwarding, NAT masquerade |
| `hosts/protecli-vault/modules/firewall.nix` | nftables ruleset: inet filter table (input/forward/output chains), ip nat table, drop logging |
| `hosts/protecli-vault/modules/services.nix` | Pi-hole Docker container, Unbound NixOS service, DNS/DHCP firewall port allowances |

### Notes

- Follow the repository's self-contained host pattern (homelab, bee-gpu-server) -- do NOT import shared `commonModules`.
- Use `{config, pkgs, lib, ...}:` function signature in all `.nix` modules.
- Use `mainUser = "bee"` as a `let` binding, referenced via `${mainUser}`.
- Format all `.nix` files with `alejandra` (never nixfmt). `rebuild.sh` runs this automatically.
- Never hand-edit `hardware-configuration.nix` -- it is generated on the device.
- Never hardcode passwords, keys, or tokens in `.nix` files.
- `stateVersion = "25.05"` for both system and home-manager.
- Access unstable packages via `pkgs.unstable.<package>` through the existing overlay.
- Interface names (e.g., `enp1s0`) are placeholders. Replace with actual names from `ip link` on the physical device after NixOS installation.

## Tasks

### [x] 1.0 Host Definition, Base System, and Remote Deployment

#### 1.0 Proof Artifact(s)

- CLI: `nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run` completes without errors demonstrates the host is defined in the flake and evaluates successfully
- Diff: `flake.nix` diff shows new `protecli-vault` entry under `nixosConfigurations` following the homelab pattern (unstable overlay + home-manager + self-contained host module) demonstrates flake integration
- Diff: `rebuild.sh` diff shows new `--protecli-vault` flag with `PROTECLI_VAULT_HOST="bee@192.168.100.1"` variable demonstrates remote deployment integration
- CLI: `alejandra --check .` passes with no formatting errors demonstrates code follows repository formatting standards

#### 1.0 Tasks

- [x] 1.1 Create a placeholder `hosts/protecli-vault/hardware-configuration.nix` that allows the flake to evaluate. Use a minimal valid structure with `modulesPath + "/installer/scan/not-detected.nix"` import, an empty `boot.initrd.availableKernelModules` list, and a temporary root filesystem definition. Add a comment at the top: `# PLACEHOLDER: Replace with output of nixos-generate-config on the physical device`. This file will be replaced entirely once the device is available.
- [x] 1.2 Create `hosts/protecli-vault/home/default.nix` with a minimal home-manager configuration. Copy the exact pattern from `hosts/homelab/home/default.nix`: `mainUser = "bee"`, `home-manager.useGlobalPkgs/useUserPackages/backupFileExtension`, zsh with autosuggestion + syntax highlighting + oh-my-zsh plugins (colored-man-pages, colorize, history-substring-search), oh-my-posh init, rebuild alias, and the oh-my-posh theme xdg config file sourced from `../../../config/oh-my-posh-theme.json`.
- [x] 1.3 Create `hosts/protecli-vault/default.nix` as the main host configuration. Use `{config, pkgs, lib, ...}: let mainUser = "bee"; in { ... }`. Include `imports` for `./hardware-configuration.nix`, `./home`, `./modules/networking.nix`, `./modules/firewall.nix`, and `./modules/services.nix`. Add: `boot.loader.systemd-boot.enable = true` and `boot.loader.efi.canTouchEfiVariables = true` (UEFI boot), `networking.hostName = "protecli-vault"`, user `${mainUser}` with groups `["wheel" "docker"]` and `shell = pkgs.zsh`, `services.openssh` with `PermitRootLogin = "no"` and `PasswordAuthentication = true`, `services.tailscale` (enabled, `pkgs.unstable.tailscale`, `openFirewall = true`), `virtualisation.docker.enable = true`, `programs.zsh.enable = true`, passwordless sudo via `security.sudo.extraRules` (same pattern as homelab), `nixpkgs.config.allowUnfree = true`, `nix.settings.experimental-features = ["nix-command" "flakes"]`, `nix.settings.trusted-users = ["root" "bee"]`, timezone, locale, `system.stateVersion = "25.05"`, and a minimal `environment.systemPackages` (vim, wget, curl, git, htop, tmux, tree, alejandra, ethtool, tcpdump, dig, nftables, iperf3).
- [x] 1.4 Create empty stub files for `hosts/protecli-vault/modules/networking.nix`, `hosts/protecli-vault/modules/firewall.nix`, and `hosts/protecli-vault/modules/services.nix`. Each should contain `{config, pkgs, lib, ...}: { }` (valid empty module) so the imports in `default.nix` resolve without errors.
- [x] 1.5 Add the `protecli-vault` entry to `flake.nix` under `nixosConfigurations`. Follow the homelab/bee-gpu-server pattern exactly: `protecli-vault = nixpkgs.lib.nixosSystem { inherit system; modules = [ {nixpkgs.overlays = [unstableOverlay];} home-manager.nixosModules.default ./hosts/protecli-vault ]; };`
- [x] 1.6 Add `--protecli-vault` support to `rebuild.sh`. Add `PROTECLI_VAULT_HOST="bee@192.168.100.1"` to the host variables at the top. Add `PROTECLI_VAULT=false` to the flag defaults. Add `--protecli-vault) PROTECLI_VAULT=true ;;` to the case statement. Add an `elif $PROTECLI_VAULT; then` block following the existing `elif $BEE_GPU_SERVER` block, using `nixos-rebuild "$ACTION" --flake .#protecli-vault --target-host "$PROTECLI_VAULT_HOST" --use-remote-sudo &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)`.
- [x] 1.7 Run `alejandra .` to format all new files, then verify with `nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run` that the flake evaluates successfully.

### [~] 2.0 Network Interfaces, Bridge, and Routing with NAT

#### 2.0 Proof Artifact(s)

- CLI: `ssh bee@<vault-ip> ip addr show br-lan` shows `10.0.0.1/24` assigned demonstrates the LAN bridge is configured with the correct IP
- CLI: `ssh bee@<vault-ip> ip addr show <mgmt-interface>` shows `192.168.100.1/24` demonstrates the management port is on a separate subnet
- CLI: `ssh bee@<vault-ip> sysctl net.ipv4.ip_forward` returns `net.ipv4.ip_forward = 1` demonstrates IPv4 forwarding is enabled
- CLI: `ssh bee@<vault-ip> nft list ruleset` shows `oifname "<wan>" masquerade` in a NAT postrouting chain demonstrates NAT masquerade is configured
- CLI: from a device connected to a LAN port, `ping 8.8.8.8` succeeds demonstrates end-to-end routing through the Vault to the internet

#### 2.0 Tasks

- [x] 2.1 In `hosts/protecli-vault/modules/networking.nix`, define `let` bindings at the top of the module for interface names: `wan = "enp1s0"; lan1 = "enp2s0"; lan2 = "enp3s0"; lan3 = "enp4s0"; lan4 = "enp5s0"; mgmt = "enp6s0";`. Add a comment: `# PLACEHOLDER interface names -- replace with actual names from 'ip link' on the physical device`. These names follow predictable naming for Intel i211 NICs but must be confirmed on hardware.
- [x] 2.2 In the same module, set `networking.useNetworkd = true;` and `networking.useDHCP = lib.mkForce false;` to switch from NetworkManager to systemd-networkd. Disable NetworkManager explicitly: `networking.networkmanager.enable = false;`. Disable the NixOS default firewall and NAT modules: `networking.firewall.enable = lib.mkForce false;` and `networking.nat.enable = false;`.
- [x] 2.3 Enable IPv4 forwarding via kernel sysctl: `boot.kernel.sysctl = { "net.ipv4.conf.all.forwarding" = true; };`. Add this to the networking module since it is a routing concern.
- [x] 2.4 Create the `br-lan` bridge netdev using `systemd.network.netdevs`: define a `"20-br-lan"` entry with `netdevConfig = { Kind = "bridge"; Name = "br-lan"; };`.
- [x] 2.5 Enslave the 4 LAN interfaces to the bridge. For each LAN interface (`lan1` through `lan4`), create a `systemd.network.networks` entry (e.g., `"30-${lan1}"`) with `matchConfig.Name = lan1;`, `networkConfig = { Bridge = "br-lan"; ConfigureWithoutCarrier = true; };`, and `linkConfig.RequiredForOnline = "enslaved";`. Use a helper function or `lib.mergeAttrsList (map enslaveToBridge [lan1 lan2 lan3 lan4])` to avoid repetition, following the pattern from NixOS router community guides.
- [x] 2.6 Configure the WAN interface. Create a `systemd.network.networks` entry `"10-wan"` with `matchConfig.Name = wan;`, `networkConfig.DHCP = "ipv4";` (get IP from ISP router), `networkConfig.IPv4Forwarding = true;`, and `linkConfig.RequiredForOnline = "routable";`.
- [x] 2.7 Configure the `br-lan` bridge network. Create a `systemd.network.networks` entry `"40-br-lan"` with `matchConfig.Name = "br-lan";`, `address = ["10.0.0.1/24"];`, `networkConfig.ConfigureWithoutCarrier = true;`, and `linkConfig.RequiredForOnline = "no";`.
- [x] 2.8 Configure the management port. Create a `systemd.network.networks` entry `"10-mgmt"` with `matchConfig.Name = mgmt;`, `address = ["192.168.100.1/24"];`, `networkConfig.ConfigureWithoutCarrier = true;`, and `linkConfig.RequiredForOnline = "no";`.
- [x] 2.9 Set `systemd.network.wait-online.anyInterface = true;` so the system doesn't block boot waiting for all interfaces to come up.
- [x] 2.10 Disable `services.resolved` since DNS will be handled by Pi-hole and Unbound: `services.resolved.enable = false;`.
- [x] 2.11 Add the NAT masquerade rule. In `networking.nftables.enable = true;` (already set by the firewall module -- see task 3.1), add a `table ip nat` with a `chain postrouting` of `type nat hook postrouting priority 100; policy accept;` containing `oifname "${wan}" masquerade`. This can be placed in the networking module or the firewall module -- place it in `firewall.nix` alongside the filter rules to keep all nftables configuration in one file. Coordinate with task 3.0.
- [x] 2.12 Run `alejandra .` and verify the module evaluates: `nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run`.

### [ ] 3.0 nftables Firewall Rules and Management Port Safety

#### 3.0 Proof Artifact(s)

- CLI: `ssh bee@<vault-ip> nft list ruleset` shows complete `inet filter` table with `input` (policy drop), `forward` (policy drop), and `ip nat` table with `postrouting` chain demonstrates full firewall and NAT ruleset is applied
- CLI: `ssh bee@<vault-ip> nft list chain inet filter input` shows management interface accept rule as the first non-loopback rule demonstrates management port lockout protection
- CLI: from a device on the WAN side, `nmap -p 22 <vault-wan-ip>` shows port 22 as filtered/closed demonstrates SSH is not exposed on WAN
- CLI: `ssh bee@192.168.100.1 hostname` returns `protecli-vault` while a broken LAN rule is active demonstrates management port SSH survives firewall misconfigurations
- CLI: `ssh bee@<vault-ip> journalctl -k --no-pager | grep -c "dropped"` returns a non-zero count after sending test traffic demonstrates firewall drop logging with rate limiting is active

#### 3.0 Tasks

- [ ] 3.1 In `hosts/protecli-vault/modules/firewall.nix`, import the interface name variables. Either re-define the same `let` bindings as in `networking.nix` (wan, mgmt interface names), or refactor both modules to share a common `let` block via a shared file or by moving interface name definitions to `default.nix` and passing them as module arguments. The simplest approach for now: duplicate the `let` bindings at the top of `firewall.nix` with a comment `# Must match interface names in networking.nix`.
- [ ] 3.2 Enable nftables and disable the default NixOS firewall. Set `networking.nftables.enable = true;` and `networking.nftables.checkRuleset = false;` (disable ruleset checking which can fail in sandboxed builds). Ensure `networking.firewall.enable = lib.mkForce false;` is set (may already be in networking.nix -- ensure no conflict by using `lib.mkForce` in one location).
- [ ] 3.3 Write the complete nftables ruleset in `networking.nftables.ruleset`. Define two tables: (1) `table inet filter` with chains `input`, `forward`, and `output`; (2) `table ip nat` with chain `postrouting`. The `output` chain should use `policy accept`.
- [ ] 3.4 Write the `input` chain rules in order: `type filter hook input priority 0; policy drop;` then: (a) `iifname "${mgmt}" accept comment "SAFETY: management port always allowed"` (first rule, lockout protection), (b) `iifname "lo" accept comment "allow loopback"`, (c) `iifname "br-lan" accept comment "allow LAN traffic to router"`, (d) `iifname "tailscale0" accept comment "allow Tailscale traffic"`, (e) `iifname "${wan}" ct state { established, related } accept comment "allow established WAN traffic"`, (f) `iifname "${wan}" icmp type { echo-request, destination-unreachable, time-exceeded } counter accept comment "allow select ICMP from WAN"`, (g) `iifname "${wan}" counter log prefix "dropped: " limit rate 5/minute drop comment "log and drop all other WAN input"`.
- [ ] 3.5 Write the `forward` chain rules: `type filter hook forward priority 0; policy drop;` then: (a) `iifname "br-lan" oifname "${wan}" accept comment "allow LAN to WAN"`, (b) `iifname "${wan}" oifname "br-lan" ct state { established, related } accept comment "allow established WAN to LAN"`, (c) `counter log prefix "dropped forward: " limit rate 5/minute drop comment "log and drop other forwarded traffic"`.
- [ ] 3.6 Write the `postrouting` NAT chain (if not already placed in networking.nix per task 2.11): `table ip nat { chain postrouting { type nat hook postrouting priority 100; policy accept; oifname "${wan}" masquerade comment "NAT LAN traffic to WAN"; } }`.
- [ ] 3.7 Run `alejandra .` and verify: `nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run`.

### [ ] 4.0 DHCP and DNS Services (Pi-hole Docker + Unbound NixOS Service)

#### 4.0 Proof Artifact(s)

- CLI: `ssh bee@<vault-ip> docker ps --filter name=pihole --format '{{.Status}}'` shows `Up` demonstrates Pi-hole container is running
- CLI: `ssh bee@<vault-ip> systemctl is-active unbound` returns `active` demonstrates Unbound NixOS service is running
- CLI: `ssh bee@<vault-ip> dig +short google.com @127.0.0.1 -p 5335` returns a valid IP address demonstrates Unbound recursive DNS resolution works independently
- CLI: from a LAN client with no static IP, `ip addr show` shows an IP in the `10.0.0.50-254` range with gateway `10.0.0.1` demonstrates Pi-hole DHCP is assigning addresses correctly
- CLI: from a LAN client, `nslookup google.com 10.0.0.1` returns a valid IP demonstrates DNS resolution works through Pi-hole to Unbound
- CLI: from a LAN client, `nslookup doubleclick.net 10.0.0.1` returns `0.0.0.0` or NXDOMAIN demonstrates Pi-hole ad blocking is active
- Browser: `http://10.0.0.1/admin` loads the Pi-hole web admin dashboard demonstrates the admin interface is accessible from LAN

#### 4.0 Tasks

- [ ] 4.1 In `hosts/protecli-vault/modules/services.nix`, configure the Unbound NixOS service. Set `services.unbound.enable = true;` with settings: `server.interface = ["127.0.0.1"];`, `server.port = 5335;`, `server.access-control = ["127.0.0.0/8 allow"];`, `server.do-not-query-localhost = false;`. Enable DNSSEC validation with `server.auto-trust-anchor-file` (NixOS sets this automatically when `services.unbound.enable = true`). Set `server.verbosity = 1;` for basic logging. Add `server.num-threads = 2;` (match the i5-7200U's 2 cores). Set `server.hide-identity = true;` and `server.hide-version = true;` for security.
- [ ] 4.2 Configure the Pi-hole Docker container using `virtualisation.oci-containers`. Set `backend = "docker";` and define a `pihole` container with: `image = "pihole/pihole:latest";`, `extraOptions = ["--network=host"];` (required for DHCP broadcast traffic on br-lan), environment variables: `TZ = "America/Los_Angeles"`, `DNSMASQ_LISTENING = "local"`, `PIHOLE_DNS_ = "127.0.0.1#5335"` (point to Unbound), `DHCP_ACTIVE = "true"`, `DHCP_START = "10.0.0.50"`, `DHCP_END = "10.0.0.254"`, `DHCP_ROUTER = "10.0.0.1"`, `PIHOLE_DOMAIN = "lan"`, `DHCP_LEASETIME = "24"`, `REV_SERVER = "false"`, `WEBPASSWORD = ""` (empty -- set manually post-deploy for security). Mount a persistent volume: `volumes = ["/var/lib/pihole/etc-pihole:/etc/pihole" "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"];`.
- [ ] 4.3 Create the Pi-hole persistent data directories. Add a `systemd.tmpfiles.rules` entry to create `/var/lib/pihole/etc-pihole` and `/var/lib/pihole/etc-dnsmasq.d` with appropriate ownership so they exist before the Docker container starts: `["d /var/lib/pihole/etc-pihole 0755 root root -" "d /var/lib/pihole/etc-dnsmasq.d 0755 root root -"]`.
- [ ] 4.4 Ensure the Unbound service starts before the Pi-hole container. Add `systemd.services.docker-pihole.after = ["unbound.service"];` and `systemd.services.docker-pihole.requires = ["unbound.service"];` so Pi-hole's upstream DNS is available when it starts.
- [ ] 4.5 Ensure the NixOS-managed `systemd-resolved` stub listener on port 53 does not conflict with Pi-hole. Verify that `services.resolved.enable = false;` is set (from task 2.10). If NixOS enables any default DNS listener, ensure it is disabled so Pi-hole can bind to port 53 on `10.0.0.1`.
- [ ] 4.6 Add `dnsutils` (provides `dig` and `nslookup`) to `environment.systemPackages` in `hosts/protecli-vault/default.nix` for DNS troubleshooting on the Vault itself.
- [ ] 4.7 Run `alejandra .` and verify: `nix build .#nixosConfigurations.protecli-vault.config.system.build.toplevel --dry-run`.
