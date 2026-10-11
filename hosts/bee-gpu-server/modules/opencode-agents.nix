# Host-local OpenCode sandbox instances for bee-gpu-server (Spec 18).
#
# One roster entry becomes one unprivileged systemd-nspawn container with a
# private network namespace, running the pinned OpenCode v2 build as the
# unprivileged `agent` user. Egress is enforced on the host by
# ./opencode-egress.nix.
#
# The derived instance values are exposed to that module through the internal
# `opencodeSandbox.instances` option so the roster and its consumers stay in
# sync. Derived values are a pure function of `index`:
#
#   uidBase      = 1048576 + index * 65536
#   serverPort   = 41800 + index
#   proxyPort    = 43100 + index
#   hostAddress  = 10.201.<index>.1
#   localAddress = 10.201.<index>.2   (the module applies /32)
#
# `uidBase` is a multiple of 65536 (2^16) because nspawn's
# `--private-users-ownership=chown` (needed so the container can write the /etc
# and /var directories the NixOS container wrapper creates as real root) only
# supports UID ranges starting at a multiple of 2^16. The spec's proposed
# `1000000 + index*65536` cannot be chowned and is therefore adjusted here
# (Spec 18 Open Question #5).
{
  config,
  pkgs,
  lib,
  ...
}: let
  # Provided by the host's `unstable` aspect. The container is evaluated against
  # a fresh nixpkgs and does NOT inherit host overlays (Spec 18 Open Question #3),
  # so the pinned build is captured here and referenced from the container.
  opencodePkg = pkgs.opencodeV2;

  modelPort = 8080;
  modelAlias = "qwen3.8-flash-next";
  # Sentinel used until the operator provisions a scoped PAT (see the runbook).
  # While it is in place the container clones the (public) repo anonymously.
  gitPatPlaceholder = "REPLACE_WITH_SCOPED_PAT";

  agentUid = 1000;
  agentGid = 1000;

  # v1 ships exactly one pilot entry (Spec 18 Open Question #1:
  # myles-coleman/nixos). The roster is list-driven; add a new entry with the
  # next free index, its sops secrets, and its Tailscale ACL range.
  roster = [
    {
      name = "nixos";
      repoUrl = "https://github.com/myles-coleman/nixos.git";
      index = 0;
    }
  ];

  derive = inst: rec {
    inherit (inst) name repoUrl index;
    uidBase = 1048576 + index * 65536;
    serverPort = 41800 + index;
    proxyPort = 43100 + index;
    hostAddress = "10.201.${toString index}.1";
    localIp = "10.201.${toString index}.2";
    # The nixos-containers module uses this verbatim both as the container's
    # eth0 address and as `ip route add <localAddress>`, so it must be a bare
    # host address (the module applies /32); "10.201.<index>.2/30" makes the
    # host route invalid.
    localAddress = localIp;
    dataDir = "/srv/oc/${name}";
    repoDir = "/srv/oc/${name}/repo";
    hostUid = uidBase + agentUid;
    hostGid = uidBase + agentGid;
  };

  instances = map derive roster;

  opencodeJson = inst: {
    "$schema" = "https://opencode.ai/config.json";
    username = "opencode-${inst.name}";
    model = "qwen-local/${modelAlias}";
    enabled_providers = ["qwen-local"];
    provider.qwen-local = {
      npm = "@ai-sdk/openai-compatible";
      name = "Qwen Local (llama.cpp on bee-gpu-server)";
      options = {
        # An IP literal so the container needs no DNS to reach the model.
        baseURL = "http://${inst.hostAddress}:${toString modelPort}/v1";
        apiKey = "not-needed";
      };
      models.${modelAlias} = {
        name = "Qwen3.8 Flash Next (local)";
        id = modelAlias;
      };
    };
    tools = {
      webfetch = false;
      websearch = false;
    };
    # Unattended instances must never block on `ask`.
    permission = {
      read = "allow";
      edit = "allow";
      glob = "allow";
      grep = "allow";
      list = "allow";
      bash = "allow";
      task = "allow";
      external_directory = "allow";
      todowrite = "allow";
      lsp = "allow";
      skill = "allow";
      webfetch = "deny";
      websearch = "deny";
      question = "deny";
    };
  };

  mkOpencodeInstance = inst: let
    serverPasswordSecret = "${inst.name}_server_password";
    gitPatSecret = "${inst.name}_git_pat";
  in {
    systemd.tmpfiles.rules = [
      "d /srv/oc 0755 root root -"
      "d ${inst.dataDir} 0700 ${toString inst.hostUid} ${toString inst.hostGid} -"
      # The clone target. Created empty so opencode-serve's WorkingDirectory
      # exists before the (post-boot, retried) clone populates it.
      "d ${inst.repoDir} 0700 ${toString inst.hostUid} ${toString inst.hostGid} -"
    ];

    # Per-instance secrets: decrypted on the host and delivered into the
    # container via nspawn credentials (never in a .nix file or argv). A
    # rotation restarts the container so the new credential is picked up.
    sops.secrets.${serverPasswordSecret} = {
      owner = "root";
      mode = "0400";
      restartUnits = ["container@${inst.name}.service"];
    };
    sops.secrets.${gitPatSecret} = {
      owner = "root";
      mode = "0400";
      restartUnits = ["container@${inst.name}.service"];
    };

    # Start the container only after sops has written the decrypted secrets.
    systemd.services."container@${inst.name}" = {
      wants = ["sops-install-secrets.service"];
      after = ["sops-install-secrets.service"];
    };

    containers.${inst.name} = {
      autoStart = true;
      privateNetwork = true;
      privateUsers = inst.uidBase;
      hostAddress = inst.hostAddress;
      localAddress = inst.localAddress;
      # Deliberate: unrelated host rebuilds must not kill in-flight sessions.
      # A container config change needs a manual `systemctl restart`.
      restartIfChanged = false;
      extraFlags = [
        # NixOS creates the container root's /etc, /var as real root before
        # nspawn starts. With `--private-users`, nspawn's default `map`
        # ownership leaves those host-root files as `nobody` inside the
        # namespace, so container activation fails. Force a chown to the
        # mapped range instead.
        "--private-users-ownership=chown"
        "--load-credential=opencode-server-password:${config.sops.secrets.${serverPasswordSecret}.path}"
        "--load-credential=git-pat:${config.sops.secrets.${gitPatSecret}.path}"
      ];
      # /nix/store, the Nix DB and the host Nix daemon socket are already
      # bind-mounted read-only (and idmap-aware) by the nixos-containers
      # machinery, so only the container-owned data dir needs an explicit bind.
      bindMounts.${inst.dataDir} = {
        hostPath = inst.dataDir;
        isReadOnly = false;
      };

      config = {pkgs, ...}: let
        configFile = pkgs.writeText "opencode.json" (builtins.toJSON (opencodeJson inst));
        askpass = pkgs.writeShellScript "opencode-git-askpass" ''
          case "$1" in
            Username*) printf '%s' "x-access-token" ;;
            Password*) cat "$CREDENTIALS_DIRECTORY/git-pat" ;;
          esac
        '';
        proxyUrl = "http://${inst.hostAddress}:${toString inst.proxyPort}";
        # The container has no direct egress; the clone and every server fetch
        # must go through the instance's squid listener.
        proxyEnv = {
          HTTP_PROXY = proxyUrl;
          HTTPS_PROXY = proxyUrl;
          http_proxy = proxyUrl;
          https_proxy = proxyUrl;
          NO_PROXY = "${inst.hostAddress},127.0.0.1,localhost";
          no_proxy = "${inst.hostAddress},127.0.0.1,localhost";
        };
        serveScript = pkgs.writeShellScript "opencode-serve-${inst.name}" ''
          set -eu
          export OPENCODE_SERVER_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/opencode-server-password")"
          exec ${opencodePkg}/bin/opencode serve --hostname ${inst.localIp} --port ${toString inst.serverPort}
        '';
      in {
        system.stateVersion = "25.05";

        environment.systemPackages = [
          opencodePkg
          pkgs.git
          pkgs.curl
          pkgs.cacert
        ];

        # The single unprivileged user that runs the server and owns the clone.
        users.users.agent = {
          isNormalUser = true;
          uid = agentUid;
          group = "agent";
          home = inst.dataDir;
          createHome = false;
          shell = pkgs.bashInteractive;
        };
        users.groups.agent.gid = agentGid;

        # Every XDG/data directory lives under the container-owned data dir.
        environment.variables = {
          NIX_REMOTE = "daemon";
          XDG_DATA_HOME = "${inst.dataDir}/.local/share";
          XDG_CACHE_HOME = "${inst.dataDir}/.cache";
          XDG_CONFIG_HOME = "${inst.dataDir}/.config";
          XDG_STATE_HOME = "${inst.dataDir}/.local/state";
        };

        # No DNS egress tunnel: the only routed address is the host veth, name
        # resolution for allowlisted traffic is done by the proxy, and the model
        # baseURL is an IP literal.
        networking.resolvconf.enable = false;
        networking.nameservers = [];

        # The container firewall is enabled by default; eth0 is a point-to-point
        # veth to the host, so opening only the server port keeps the instance
        # reachable from the host (and thus the tailnet DNAT) but nothing else.
        networking.firewall.allowedTCPPorts = [inst.serverPort];

        # Deliberately absent: services.openssh, Docker/Podman, GPU devices,
        # ssh-agent. The container is a fresh nixpkgs eval and inherits none of
        # the host's aspects or devices.

        # Re-assert agent ownership of the (bind-mounted) home in case the
        # container root or a previous run left it otherwise.
        systemd.tmpfiles.rules = [
          "z ${inst.dataDir} 0700 agent agent -"
        ];

        # Create the XDG directories and write opencode.json. Runs as root so it
        # can fix ownership deterministically regardless of what a previous run
        # left behind; the server depends on it directly, and it needs no
        # network.
        systemd.services.opencode-setup = {
          description = "Write the OpenCode config (${inst.name})";
          wantedBy = ["multi-user.target"];
          before = ["opencode-serve.service"];
          requiredBy = ["opencode-serve.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -eu
            umask 077
            install -d -m 0700 ${inst.dataDir}/.config/opencode
            install -d -m 0700 ${inst.dataDir}/.cache
            install -d -m 0700 ${inst.dataDir}/.local/share
            install -d -m 0700 ${inst.dataDir}/.local/state
            chown -R agent:agent ${inst.dataDir}/.config ${inst.dataDir}/.cache ${inst.dataDir}/.local
            install -m 0644 -o agent -g agent ${configFile} ${inst.dataDir}/.config/opencode/opencode.json
          '';
        };

        # Idempotent clone of the container-owned workspace. It cannot run during
        # the container boot: the only egress path is the host squid proxy, whose
        # listener (on the veth address) and the veth address itself only come up
        # after the container signals ready. So it is triggered by a timer after
        # boot and retried until the proxy is reachable.
        systemd.services.opencode-clone = {
          description = "Clone the OpenCode workspace (${inst.name})";
          unitConfig.ConditionPathExists = "!${inst.repoDir}/.git";
          path = [pkgs.git pkgs.coreutils pkgs.cacert];
          environment = proxyEnv;
          serviceConfig = {
            Type = "oneshot";
            User = "agent";
            Group = "agent";
            LoadCredential = ["git-pat"];
          };
          script = ''
            set -eu
            # Supply the PAT only when a real one is present. The URL never
            # embeds it, so it stays out of argv, the remote, and the logs.
            pat=""
            if [ -r "$CREDENTIALS_DIRECTORY/git-pat" ]; then
              pat="$(cat "$CREDENTIALS_DIRECTORY/git-pat")"
            fi
            if [ -n "$pat" ] && [ "$pat" != "${gitPatPlaceholder}" ]; then
              export GIT_ASKPASS=${askpass}
              export GIT_TERMINAL_PROMPT=0
            fi
            git clone ${inst.repoUrl} ${inst.repoDir}
            git -C ${inst.repoDir} remote set-url origin ${inst.repoUrl}
          '';
        };
        systemd.timers.opencode-clone = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "20s";
            OnUnitInactiveSec = "120s";
          };
        };

        # The pinned OpenCode v2 server. The password is read from
        # $CREDENTIALS_DIRECTORY by the wrapper script so it never appears in
        # the unit Environment= or in the process argv.
        systemd.services.opencode-serve = {
          description = "OpenCode v2 server (${inst.name})";
          wantedBy = ["multi-user.target"];
          after = ["opencode-setup.service" "network.target"];
          requires = ["opencode-setup.service"];
          path = [opencodePkg pkgs.git pkgs.bash pkgs.coreutils pkgs.cacert];
          environment =
            proxyEnv
            // {
              OPENCODE_DISABLE_MODELS_FETCH = "1";
              OPENCODE_DISABLE_LSP_DOWNLOAD = "1";
              OPENCODE_DISABLE_AUTOUPDATE = "1";
              OPENCODE_SERVER_USERNAME = "opencode";
              HOME = inst.dataDir;
            };
          serviceConfig = {
            User = "agent";
            Group = "agent";
            Restart = "always";
            RestartSec = 5;
            WorkingDirectory = inst.repoDir;
            LoadCredential = ["opencode-server-password"];
            ExecStart = serveScript;
          };
        };
      };
    };
  };
in {
  options.opencodeSandbox.instances = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    internal = true;
    description = "Derived OpenCode sandbox instance roster, consumed by opencode-egress.nix.";
  };

  config = lib.mkMerge ([
      {
        opencodeSandbox.instances = instances;

        assertions = [
          {
            assertion = lib.length roster == 1;
            message = "opencode-agents: v1 supports exactly one OpenCode instance; roster has ${toString (lib.length roster)}.";
          }
          {
            assertion =
              lib.all (
                inst: let
                  hostUids = map (u: u.uid) (lib.filter (u: u.uid != null) (lib.attrValues config.users.users));
                in
                  lib.all (uid: uid < inst.uidBase || uid > inst.uidBase + 65535) hostUids
              )
              instances;
            message = "opencode-agents: an instance uid range overlaps a host user's uid.";
          }
        ];
      }
    ]
    ++ map mkOpencodeInstance instances);
}
