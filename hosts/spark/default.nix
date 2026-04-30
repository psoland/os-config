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
  ];

  home.sessionVariables = {
    NVIM_ENABLE_MINUET = "1";
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
