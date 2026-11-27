{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.users.${mainUser} = {
    programs.alacritty = {
      enable = true;
      theme = "catppuccin_mocha";
      settings = {
        font = {
          size = 16;
          normal.family = "MesloLGS Nerd Font Mono";
        };
        window = {
          opacity = 0.9;
          padding = {
            x = 10;
            y = 10;
          };
        };
      };
    };

    services.hyprpaper = {
      enable = true;
      # Config only: still generate hypr/hyprpaper.conf, but don't create the
      # systemd user service. hyprpaper is launched by ~/.config/hypr/start.sh
      # (exec-once in hyprland.conf); `package = null` avoids a second daemon
      # fighting over the IPC socket once graphical-session.target is up. The
      # binary itself is on PATH via the `home-desktop` aspect's home.packages.
      package = null;
      settings = {
        ipc = "on";
        splash = false;
        preload = [
          "~/.config/wallpaper1.jpg"
        ];
        wallpaper = [
          "eDP-1,~/.config/wallpaper1.jpg"
          "DP-1,~/.config/wallpaper1.jpg"
        ];
      };
    };

    services.gammastep = {
      enable = true;
      provider = "manual";
      latitude = 37.7749;
      longitude = -122.4194;
      temperature = {
        day = 5500;
        night = 3500;
      };
      settings = {
        general = {
          brightness-day = "1.0";
          brightness-night = "0.8";
        };
      };
    };

    xdg.configFile = {
      "hypr/hyprland.conf".source = ./hyprland.conf;
      "hypr/start.sh" = {
        source = ./start.sh;
        executable = true;
      };
      "waybar/kvm-switch.sh" = {
        source = ../../../config/waybar/kvm-switch.sh;
        executable = true;
      };
      # The youtube_transcript tool: a server plugin that calls the local
      # whisper.cpp service on bee-gpu-server. Kept in Nix so the plugin and
      # the baseURL travel with the rest of the config.
      "opencode/plugins/youtube-transcript/index.ts".source =
        ../../../config/opencode/plugins/youtube-transcript/index.ts;

      "opencode/opencode.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        plugins = [
          {
            # Absolute, not "./plugins/...": a configured plugin path resolves
            # against the project directory, not against this config file, so the
            # relative form looked for <project>/plugins/youtube-transcript and
            # was skipped without a warning. Verified: the same directory loads
            # by absolute path and does not by relative.
            package = "${config.users.users.${mainUser}.home}/.config/opencode/plugins/youtube-transcript";
            options.baseURL = "https://bee-gpu-server.tail6d2e9b.ts.net";
          }
        ];
        provider = {
          qwen-local = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              # Strata on bee-gpu-server, reached over the tailnet (the two LANs
              # have no forwarding path). Replaces the dead 10.0.0.156:8080 that
              # served the retired qwen-177b container (spec 20).
              #
              # This is now the only model host. `llama.cowlab.org` was retired
              # with the llama.cpp container, and the `llama-cpp` provider that
              # still pointed at it has been removed rather than repointed:
              # keeping two provider names for one backend only splits which
              # model id a session records.
              baseURL = "http://100.127.170.8:8080/v1";
              # Strata validates the bearer token — it answers 401 to a missing
              # or wrong key, so this provider cannot authenticate anonymously.
              # `{env:...}` keeps the value out of the Nix store, which is
              # world-readable; export STRATA_API_KEY before launching, the same
              # way ~/strata-gate does, from sops:
              # secrets/hosts/bee-gpu-server.yaml -> strata_api_key.
              apiKey = "{env:STRATA_API_KEY}";
              includeUsage = true;
            };
            models = {
              "qwen3.8-flash-next" = {
                name = "Qwen3.8 Flash Next (RX 7900 XTX)";
                contextWindow = 100000;
              };
            };
          };
        };
        mcp.filesystem = {
          type = "local";
          command = [
            "npx"
            "-y"
            "@modelcontextprotocol/server-filesystem@2026.8.31"
            "${config.users.users.${mainUser}.home}/ai-artifacts-vault"
          ];
          enabled = true;
        };
        # SearXNG-backed search, with query sanitization in front of it.
        # Displaces the built-in websearch tool (see tools.websearch below).
        mcp.searxng = {
          type = "local";
          command = [
            "${config.users.users.${mainUser}.home}/agent-websearch/bin/websearch"
            "mcp"
          ];
          enabled = true;
        };
        # The built-in websearch queries a hosted Exa/Parallel backend and sends
        # the query verbatim. Leaving it enabled would mean the model sometimes
        # bypasses sanitization, so it is disabled in favour of mcp.searxng.
        #
        # webfetch is disabled because fetch_page is the stricter reader:
        # it refuses private, loopback and link-local targets, so a
        # prompt-injected page cannot use it to reach the cluster API or the
        # tailnet. Two retrieval tools would mean the weaker one gets used.
        tools.websearch = false;
        tools.webfetch = false;
      };

      # Config for the agent-websearch tool. Kept in Nix so the instance URL and
      # the sanitization policy travel with the rest of the system config.
      "websearch/config.toml".text = ''
        [searxng]
        url = "https://searxng.cowlab.org"

        [search]
        language = "en"
        safesearch = 0
        category = "general"
        limit = 10
        timeout = 25.0

        [fallback]
        enabled = true
        min_results = 3
        bangs = ["!mwm", "!br", "!ddg"]

        [throttle]
        min_interval_seconds = 1.0

        [cache]
        enabled = true
        ttl_seconds = 300

        [privacy]
        enabled = true
        strict = false
        extra_domains = ["cowlab.org"]

        [fetch]
        timeout = 20.0
        max_chars = 20000
        max_bytes = 2097152
        # Agent-fetched URLs stay on the public internet by default so a
        # prompt-injected page cannot reach the cluster API or the tailnet.
        allow_private = false
      '';
    };
  };
}
