{
  config,
  pkgs,
  lib,
  ...
}: {
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.open = true;

  # Kernel modules for NVIDIA CUDA
  boot.kernelModules = ["nvidia-uvm"];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];

  # Ollama service with GPU support
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    environmentVariables = {
      OLLAMA_HOST = "127.0.0.1:11434";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    models = "/var/lib/ollama/models";
    loadModels = ["qwen2.5-coder:7b" "qwen2.5:7b" "llama3.1:8b"];
  };

  # Allow Ollama to access GPU devices
  systemd.services.ollama = {
    serviceConfig = {
      DeviceAllow = [
        "/dev/nvidia0 rwm"
        "/dev/nvidiactl rwm"
        "/dev/nvidia-modeset rwm"
        "/dev/nvidia-uvm rwm"
        "/dev/nvidia-uvm-tools rwm"
      ];
      PrivateDevices = false;
    };
  };
}
