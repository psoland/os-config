{ pkgs, ... }:

{

  imports = [
    ../../modules/common.nix
    ../../modules/caddy.nix
  ];

  home.packages = with pkgs; [
    code-server
    (llama-cpp.override { cudaSupport = true; })
    python313Packages.huggingface-hub

    (writeShellScriptBin "llama-server-cuda" ''
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

      exec llama-server "$@"
    '')

    (writeShellScriptBin "fim" ''
      set -euo pipefail

      MODEL="''${FIM_MODEL:-ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF}"
      HOST="''${FIM_HOST:-127.0.0.1}"
      PORT="''${FIM_PORT:-8012}"
      NGL="''${FIM_NGL:-99}"
      FLASH_ATTN="''${FIM_FLASH_ATTN:-on}"
      UBATCH="''${FIM_UBATCH:-1024}"
      BATCH="''${FIM_BATCH:-1024}"
      CTX_SIZE="''${FIM_CTX_SIZE:-0}"
      CACHE_REUSE="''${FIM_CACHE_REUSE:-256}"

      exec llama-server-cuda \
        -hf "$MODEL" \
        --host "$HOST" \
        --port "$PORT" \
        -ngl "$NGL" \
        --flash-attn "$FLASH_ATTN" \
        -ub "$UBATCH" -b "$BATCH" \
        --ctx-size "$CTX_SIZE" \
        --cache-reuse "$CACHE_REUSE" \
        "$@"
    '')

    (writeShellScriptBin "vllm-serve" ''
      set -euo pipefail

      usage() {
        echo "Usage: vllm-serve <name> <model> <host-port> [vllm args...]" >&2
        echo "Example: vllm-serve borealis NbAiLab/borealis-27b 8015 --gpu-memory-utilization 0.70" >&2
      }

      if [ "$#" -lt 3 ]; then
        usage
        exit 1
      fi

      NAME="$1"
      MODEL="$2"
      HOST_PORT="$3"
      shift 3

      IMAGE="''${VLLM_IMAGE:-vllm/vllm-openai:v0.24.0}"
      GPUS="''${VLLM_GPUS:-all}"
      HF_CACHE="''${VLLM_HF_CACHE:-$HOME/.cache/huggingface}"
      GPU_MEMORY_UTILIZATION="''${VLLM_GPU_MEMORY_UTILIZATION:-0.70}"

      if docker inspect "$NAME" >/dev/null 2>&1; then
        if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = "true" ]; then
          echo "Container '$NAME' is already running."
          echo "Logs: vllm-log $NAME"
          exit 0
        fi

        echo "Starting existing container '$NAME'. Use vllm-rm $NAME to recreate it with new settings."
        exec docker start "$NAME"
      fi

      exec docker run -d \
        --name "$NAME" \
        --restart unless-stopped \
        --gpus "$GPUS" \
        --ipc=host \
        --label dotfiles.service=vllm \
        --label "dotfiles.vllm.model=$MODEL" \
        -p "127.0.0.1:$HOST_PORT:8000" \
        -v "$HF_CACHE:/root/.cache/huggingface" \
        "$IMAGE" \
        "$MODEL" \
        --host 0.0.0.0 \
        --port 8000 \
        --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
        "$@"
    '')

    (writeShellScriptBin "vllm-log" ''
      set -euo pipefail

      if [ "$#" -ne 1 ]; then
        echo "Usage: vllm-log <name>" >&2
        exit 1
      fi

      exec docker logs -f "$1"
    '')

    (writeShellScriptBin "vllm-stop" ''
      set -euo pipefail

      if [ "$#" -lt 1 ]; then
        echo "Usage: vllm-stop <name> [name...]" >&2
        exit 1
      fi

      exec docker stop "$@"
    '')

    (writeShellScriptBin "vllm-rm" ''
      set -euo pipefail

      if [ "$#" -lt 1 ]; then
        echo "Usage: vllm-rm <name> [name...]" >&2
        exit 1
      fi

      exec docker rm -f "$@"
    '')

    (writeShellScriptBin "vllm-ps" ''
      set -euo pipefail

      exec docker ps -a \
        --filter label=dotfiles.service=vllm \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}'
    '')
  ];

  home.sessionVariables = {
    NVIM_ENABLE_MINUET = "1";
  };

  programs.zsh.shellAliases = {
    # llama.cpp helpers (Spark-only)
    lls = "llama-server-cuda";
    fim-start = "tmux has-session -t fim-serve 2>/dev/null || tmux new-session -d -s fim-serve 'fim'";
    fim-start-debug = "tmux has-session -t fim-serve 2>/dev/null || tmux new-session -d -s fim-serve 'fim --log-timestamps --log-prefix --log-verbosity 4'";
    fim-log = "tmux attach-session -t fim-serve";
    fim-stop = "tmux kill-session -t fim-serve";

    # vLLM Docker helpers (Spark-only)
    borealis-start = "vllm-serve borealis NbAiLab/borealis-27b 8015";
    borealis-log = "vllm-log borealis";
    borealis-stop = "vllm-stop borealis";
    borealis-rm = "vllm-rm borealis";
    vllm-list = "vllm-ps";
  };

  systemd.user.services.code-server = {
    Unit = {
      Description = "code-server";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.code-server}/bin/code-server --bind-addr 127.0.0.1:8080 --auth none";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.cloudflared = {
    Unit = {
      Description = "Cloudflare Tunnel";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %h/.config/cloudflared/token";
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home.stateVersion = "25.11";

}
