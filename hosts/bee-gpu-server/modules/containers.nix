{
  config,
  pkgs,
  lib,
  ...
}: let
  mainUser = "bee";
in {
  # Docker
  virtualisation.docker.enable = true;

  # Declarative Docker containers
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      qwen-177b = {
        image = "ghcr.io/ggml-org/llama.cpp:server-rocm@sha256:b54c5c6adb542a396885b4b07a5159e9ab0c649e007cc9f7f088799043cc9e4f";
        ports = [
          "8080:8080/tcp"
        ];
        volumes = [
          "/home/${mainUser}/models:/models"
        ];
        extraOptions = [
          "--device=/dev/dri/renderD128:/dev/dri/renderD128"
          "--device=/dev/kfd:/dev/kfd"
          "--group-add=video"
          "--group-add=render"
          "--ipc=host"
          "--cap-add=SYS_PTRACE"
          "--security-opt=seccomp=unconfined"
          "--ulimit=memlock=-1"
        ];
        cmd = [
          "--host"
          "0.0.0.0"
          "--port"
          "8080"
          "-m"
          "/models/qwen-177b-atomic/Qwen3.8-Flash-Next-AD-3.84bpw-IQ4_XS-M64-00001-of-00028.gguf"
          "--jinja"
          "--alias"
          "qwen3.8-flash-next"
          "-ngl"
          "99"
          "-ncmoe"
          "32"
          "-fit"
          "off"
          "-fa"
          "on"
          "-c"
          "100000"
          "-ctk"
          "q4_0"
          "-ctv"
          "q4_0"
          "-b"
          "1024"
          "-ub"
          "512"
          "-t"
          "6"
          "-np"
          "1"
          "--temp"
          "1"
          "--top-k"
          "20"
          "--min-p"
          "0"
          "--top-p"
          "0.95"
          "--metrics"
        ];
      };
    };
  };
}
