{ pkgs, lib, ... }:

let
  pythonRuntimeLibs = lib.optionals pkgs.stdenv.isLinux [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
in
{
  packages =
    (with pkgs; [
      python312
      uv
      ruff
      ty
      just
    ])
    ++ pythonRuntimeLibs;

  enterShell = ''
    if [ -n "${lib.makeLibraryPath pythonRuntimeLibs}" ]; then
      export LD_LIBRARY_PATH="${lib.makeLibraryPath pythonRuntimeLibs}:''${LD_LIBRARY_PATH:-}"
    fi

    echo "Python development shell"
    python --version

    if [ ! -d .venv ]; then
      uv venv
    fi

    source .venv/bin/activate
  '';

  profiles.cuda.module = {
    enterShell = ''
      if [ "$(uname -s)" = "Linux" ]; then
        __cuda_driver_path=""

        for __candidate in \
          /usr/lib/aarch64-linux-gnu/libcuda.so.1 \
          /lib/aarch64-linux-gnu/libcuda.so.1 \
          /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
          /lib/x86_64-linux-gnu/libcuda.so.1 \
          /usr/lib64/libcuda.so.1 \
          /lib64/libcuda.so.1
        do
          if [ -r "$__candidate" ]; then
            __cuda_driver_path="$__candidate"
            break
          fi
        done

        if [ -n "$__cuda_driver_path" ]; then
          case ":''${LD_PRELOAD:-}:" in
            *:"$__cuda_driver_path":*)
              ;;
            *)
              if [ -n "''${LD_PRELOAD:-}" ]; then
                export LD_PRELOAD="$__cuda_driver_path:''${LD_PRELOAD}"
              else
                export LD_PRELOAD="$__cuda_driver_path"
              fi
              ;;
          esac
        else
          echo "warning: libcuda.so.1 not found; torch.cuda.is_available() may remain False"
        fi

        unset __cuda_driver_path __candidate
      fi

      echo "Python CUDA development shell"
    '';
  };
}
