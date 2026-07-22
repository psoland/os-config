# System-level vLLM defaults. Model definitions live in
# ~/.config/vllm/models.json and are reconciled with `vllmctl update`.
{
  basePort = 8015;
  image = "vllm/vllm-openai:v0.24.0";
  gpus = "all";
  gpuMemoryUtilization = 0.60;
  maxModelLen = 8192;
  restartPolicy = "on-failure:5";
  extraArgs = [ ];
}
