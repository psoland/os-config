{ pkgs, lib, ... }:

let
  vllmRegistryConfig = import ./vllm-models.nix;

  defaults = vllmRegistryConfig.defaults or { };
  basePort = defaults.basePort or 8015;
  modelDefaults = builtins.removeAttrs defaults [ "basePort" ];

  normalizeModel =
    index: model:
    let
      merged =
        modelDefaults
        // {
          port = basePort + index;
          route = "/${model.name}";
          matcher = "model_${toString index}";
        }
        // model;

      normalized = merged // {
        extraArgs = merged.extraArgs or [ ];
        maxModelLen = merged.maxModelLen or null;
      };
    in
    normalized
    // {
      configHash = builtins.hashString "sha256" (builtins.toJSON normalized);
    };

  vllmModels = lib.imap0 normalizeModel (vllmRegistryConfig.models or [ ]);

  names = map (model: model.name) vllmModels;
  routes = map (model: model.route) vllmModels;
  ports = map (model: model.port) vllmModels;
  unique = values: lib.length (lib.unique values) == lib.length values;

  tab = "\t";

  caddyRouteForModel = model: ''
    ${tab}@${model.matcher} path ${model.route} ${model.route}/*
    ${tab}handle @${model.matcher} {
    ${tab}${tab}uri strip_prefix ${model.route}
    ${tab}${tab}reverse_proxy 127.0.0.1:${toString model.port}
    ${tab}}
  '';

  caddyConfig = ''
    :8000 {
    ${lib.concatMapStringsSep "\n" caddyRouteForModel vllmModels}
    ${tab}handle {
    ${tab}${tab}respond "unknown model route" 404
    ${tab}}
    }
  '';

  vllmRegistryJson = builtins.toJSON {
    inherit defaults;
    models = vllmModels;
  };

  fimConfig = {
    model = "ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF";
    host = "127.0.0.1";
    port = 8012;
    ngl = 99;
    flashAttn = "on";
    ubatch = 1024;
    batch = 1024;
    ctxSize = 0;
    cacheReuse = 256;
  };

  fimEndpoint = "http://${fimConfig.host}:${toString fimConfig.port}/v1/completions";

  llamaCppCuda = pkgs.llama-cpp.override { cudaSupport = true; };

  llamaServerCuda = pkgs.writeShellScriptBin "llama-server-cuda" ''
    set -euo pipefail

    find_lib() {
      local name="$1"
      local found=""
      for candidate in \
        "/usr/lib/aarch64-linux-gnu/nvidia/$name" \
        "/usr/lib/aarch64-linux-gnu/$name" \
        "/lib/aarch64-linux-gnu/$name" \
        "/usr/lib/x86_64-linux-gnu/nvidia/$name" \
        "/usr/lib/x86_64-linux-gnu/$name" \
        "/lib/x86_64-linux-gnu/$name" \
        "/usr/lib64/$name" \
        "/lib64/$name"
      do
        if [ -r "$candidate" ]; then
          found="$candidate"
          break
        fi
      done
      printf '%s' "$found"
    }

    cuda_lib="$(find_lib libcuda.so.1)"
    ptxjit_lib="$(find_lib libnvidia-ptxjitcompiler.so.1)"

    if [ -z "$cuda_lib" ]; then
      echo "error: libcuda.so.1 not found in common system paths" >&2
      echo "hint: verify NVIDIA driver installation (e.g. nvidia-smi)" >&2
      exit 1
    fi

    if [ -z "$ptxjit_lib" ]; then
      echo "error: libnvidia-ptxjitcompiler.so.1 not found in common system paths" >&2
      echo "hint: install/repair NVIDIA driver runtime packages" >&2
      exit 1
    fi

    # Keep host libs out of LD_LIBRARY_PATH to avoid glibc mismatch with Nix binaries.
    preload="$cuda_lib:$ptxjit_lib"
    if [ -n "''${LD_PRELOAD:-}" ]; then
      case ":$LD_PRELOAD:" in
        *:"$cuda_lib":*) ;;
        *) preload="$preload:$LD_PRELOAD" ;;
      esac
    fi
    export LD_PRELOAD="$preload"

    exec ${llamaCppCuda}/bin/llama-server "$@"
  '';

  fim = pkgs.writeShellScriptBin "fim" ''
    set -euo pipefail

    MODEL="''${FIM_MODEL:-${fimConfig.model}}"
    HOST="''${FIM_HOST:-${fimConfig.host}}"
    PORT="''${FIM_PORT:-${toString fimConfig.port}}"
    NGL="''${FIM_NGL:-${toString fimConfig.ngl}}"
    FLASH_ATTN="''${FIM_FLASH_ATTN:-${fimConfig.flashAttn}}"
    UBATCH="''${FIM_UBATCH:-${toString fimConfig.ubatch}}"
    BATCH="''${FIM_BATCH:-${toString fimConfig.batch}}"
    CTX_SIZE="''${FIM_CTX_SIZE:-${toString fimConfig.ctxSize}}"
    CACHE_REUSE="''${FIM_CACHE_REUSE:-${toString fimConfig.cacheReuse}}"

    extra_args=()
    if [ -n "''${FIM_EXTRA_ARGS:-}" ]; then
      # Intentionally split user-provided debug/override args.
      # shellcheck disable=SC2206
      extra_args=( ''${FIM_EXTRA_ARGS} )
    fi

    exec ${llamaServerCuda}/bin/llama-server-cuda \
      -hf "$MODEL" \
      --host "$HOST" \
      --port "$PORT" \
      -ngl "$NGL" \
      --flash-attn "$FLASH_ATTN" \
      -ub "$UBATCH" -b "$BATCH" \
      --ctx-size "$CTX_SIZE" \
      --cache-reuse "$CACHE_REUSE" \
      "''${extra_args[@]}" \
      "$@"
  '';

  fimHealth = pkgs.writeShellScriptBin "fim-health" ''
    set -euo pipefail

    host="''${FIM_HOST:-${fimConfig.host}}"
    port="''${FIM_PORT:-${toString fimConfig.port}}"
    url="''${FIM_HEALTH_URL:-http://$host:$port/health}"

    ${pkgs.curl}/bin/curl --fail --silent --show-error "$url"
    echo
  '';
in
{
  assertions = [
    {
      assertion = unique names;
      message = "hosts/spark/vllm-models.nix contains duplicate vLLM model names.";
    }
    {
      assertion = unique routes;
      message = "hosts/spark/vllm-models.nix contains duplicate vLLM routes.";
    }
    {
      assertion = unique ports;
      message = "hosts/spark/vllm-models.nix contains duplicate vLLM ports.";
    }
    {
      assertion = builtins.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9_.-]*" name != null) names;
      message = "vLLM model names must be valid Docker container names.";
    }
    {
      assertion = builtins.all (route: lib.hasPrefix "/" route && !(lib.hasSuffix "/" route)) routes;
      message = "vLLM routes must start with / and must not end with /.";
    }
  ];

  home.packages = with pkgs; [
    llamaCppCuda
    python313Packages.huggingface-hub
    jq

    llamaServerCuda
    fim
    fimHealth

    (writeShellScriptBin "vllmctl" (builtins.readFile ./vllmctl.sh))

    (writeShellScriptBin "vllm-serve" ''
      set -euo pipefail

      if [ "$#" -eq 1 ]; then
        exec vllmctl start "$1"
      fi

      echo "vllm-serve has been replaced by declarative models + vllmctl." >&2
      echo "Add models to ~/.dotfiles/hosts/spark/vllm-models.nix, run apply, then:" >&2
      echo "  vllmctl start <name>" >&2
      exit 1
    '')

    (writeShellScriptBin "vllm-log" ''
      exec vllmctl logs "$@"
    '')

    (writeShellScriptBin "vllm-stop" ''
      exec vllmctl stop "$@"
    '')

    (writeShellScriptBin "vllm-rm" ''
      exec vllmctl rm "$@"
    '')

    (writeShellScriptBin "vllm-ps" ''
      exec vllmctl ps "$@"
    '')
  ];

  # This lives outside ~/.config/nvim, which is an out-of-store symlink to
  # the dotfiles checkout. Minuet reads it directly rather than inheriting a
  # shell environment variable.
  xdg.configFile."nvim-fim.lua".text = ''
    return {
      endpoint = ${builtins.toJSON fimEndpoint},
    }
  '';

  xdg.configFile."vllm/models.json".text = vllmRegistryJson + "\n";

  dotfiles.caddy.configText = caddyConfig;

  systemd.user.services.fim = {
    Unit = {
      Description = "llama.cpp FIM completion server";
      After = [ "network.target" ];
      X-Restart-Triggers = [ fim ];
      X-SwitchMethod = "restart";
    };

    Service = {
      ExecStart = "${fim}/bin/fim";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  programs.zsh.shellAliases = {
    # llama.cpp helpers
    lls = "llama-server-cuda";
    fim-start = "systemctl --user unset-environment FIM_EXTRA_ARGS; systemctl --user start fim";
    fim-restart = "systemctl --user unset-environment FIM_EXTRA_ARGS; systemctl --user restart fim";
    fim-start-debug = "systemctl --user set-environment FIM_EXTRA_ARGS='--log-timestamps --log-prefix --log-verbosity 4'; systemctl --user restart fim";
    fim-log = "journalctl --user -u fim -f";
    fim-status = "systemctl --user status fim";
    fim-stop = "systemctl --user stop fim";

    # vLLM Docker helpers
    vllm-list = "vllmctl ps";
    vllm-models = "vllmctl list";
    vllm-plan = "vllmctl plan";
    vllm-doctor = "vllmctl doctor";
    vllm-containers = "vllmctl ps";
  };
}
