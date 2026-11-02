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
      "opencode/opencode.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        provider = {
          llama-cpp = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "https://llama.cowlab.org/v1";
            };
            models = {
              "Qwen3-8B-Q4_K_M" = {
                name = "Qwen3 8B (llama.cpp GPU)";
              };
            };
          };
          qwen-local = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              # Strata on bee-gpu-server, reached over the tailnet (the two LANs
              # have no forwarding path). Replaces the dead 10.0.0.156:8080 that
              # served the retired qwen-177b container (spec 20).
              baseURL = "http://100.127.170.8:8080/v1";
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
        # webfetch is disabled for a different reason: it cannot be proxied on
        # its own, so it would be the one page-fetch path that leaks the home
        # IP. fetch_page replaces it and honours fetch.proxy.
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
        # This host already routes all traffic through the tailnet exit node
        # (protecli-vault -> Mullvad ca-van-wg-201), so page fetches are
        # tunnelled without a proxy. `direct` also ignores HTTPS_PROXY, which
        # keeps model calls and tailnet endpoints off any accidental proxy.
        # Switch to "mullvad" (needs services.mullvad-http-proxy.enable) or
        # "tailscale" (needs a proxy on the exit node) to make it explicit.
        egress = "direct"

        [fetch.proxies]
        mullvad = "http://127.0.0.1:8118"
        # Probe on a tailnet host whose own egress is the Mullvad tunnel:
        #   gost -L http://:8118 -F direct
        tailscale = "http://100.112.185.27:8118"
      '';
    };
  };
}
