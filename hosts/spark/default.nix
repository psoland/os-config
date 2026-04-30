{ pkgs, ... }:

{

  imports = [
    ../../modules/common.nix
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

  home.stateVersion = "25.11";

}
