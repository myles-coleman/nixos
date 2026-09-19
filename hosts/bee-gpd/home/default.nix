{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  home-manager.users.${mainUser} = {
    services.hyprpaper = {
      enable = true;
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
          ollama = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "http://localhost:11434/v1";
              includeUsage = true;
            };
            models = {
              "qwen2.5-coder:7b" = {
                name = "Qwen2.5 Coder 7B (Tool Calling)";
              };
              "qwen2.5:7b" = {
                name = "Qwen2.5 7B (Chat)";
              };
              "llama3.1:8b" = {
                name = "Llama 3.1 8B (Chat)";
              };
            };
          };
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
          gemma-local = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "http://10.0.0.148:8080/v1";
              includeUsage = true;
            };
            models = {
              "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf" = {
                name = "Gemma 4 26B MoE (RX 7900 XTX)";
                contextWindow = 262144;
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
      };
    };
  };
}
