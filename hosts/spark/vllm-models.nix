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
    extraArgs = [ ];
  };

  models = [
    {
      name = "borealis";
      model = "NbAiLab/borealis-27b";
      gpuMemoryUtilization = 0.60;
    }

    {
      name = "gemma4";
      model = "google/gemma-4-31B-it";
      gpuMemoryUtilization = 0.70;
    }

    {
      name = "nvidia_qwen";
      model = "nvidia/Qwen3.6-27B-NVFP4";
      gpuMemoryUtilization = 0.60;
    }
  ];
}
