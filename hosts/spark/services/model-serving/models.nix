# Single source of truth for Spark vLLM models.
#
# Adding a model should usually only require adding one entry to `models`.
# Ports are assigned automatically from `defaults.basePort` by list order.
{
  defaults = {
    basePort = 8015;
    image = "vllm/vllm-openai:v0.24.0";
    gpus = "all";
    gpuMemoryUtilization = 0.60;
    maxModelLen = 8192;
    restartPolicy = "on-failure:5";
    extraArgs = [ ];
  };

  models = [
    {
      name = "borealis";
      model = "NbAiLab/borealis-27b";
    }

    {
      name = "gemma4";
      model = "google/gemma-4-31B-it";
      gpuMemoryUtilization = 0.70;
    }

    {
      name = "nvidia_qwen";
      model = "nvidia/Qwen3.6-27B-NVFP4";
    }

    {
      name = "qwen_36_35";
      model = "Qwen/Qwen3.6-35B-A3B-FP8";
      gpuMemoryUtilization = 0.45;
    }

    {
      name = "qwen_36_27";
      model = "Qwen/Qwen3.6-27B-FP8";
      gpuMemoryUtilization = 0.45;
    }

    {
      name = "nemotron_nano_16";
      model = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16";
    }

    {
      name = "nemotron_nano_4";
      model = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4";
    }

    {
      name = "laguna";
      model = "poolside/Laguna-S-2.1";
    }

  ];
}
