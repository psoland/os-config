{
  description = "Python development shell template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Uncomment if you need unfree packages
          # config.allowUnfree = true;
        };
        lib = pkgs.lib;
        pythonBaseInputs = with pkgs; [
          python312
          uv
          ruff
          ty
          just
        ];
        torchRuntimeLibs = lib.optionals pkgs.stdenv.isLinux [
          pkgs.stdenv.cc.cc.lib
        ];
      in
      {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = pythonBaseInputs;

            shellHook = ''
              echo "Python development shell"
              python --version

              if [ ! -d .venv ]; then
                uv venv
              fi

              source .venv/bin/activate
            '';
          };

          cuda = pkgs.mkShell {
            buildInputs = pythonBaseInputs ++ torchRuntimeLibs;

            shellHook = ''
              if [ "$(uname -s)" = "Linux" ]; then
                __torch_runtime_lib_path="${lib.makeLibraryPath torchRuntimeLibs}"
                __cuda_driver_path=""

                if [ -n "$__torch_runtime_lib_path" ]; then
                  if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
                    export LD_LIBRARY_PATH="$__torch_runtime_lib_path:''${LD_LIBRARY_PATH}"
                  else
                    export LD_LIBRARY_PATH="$__torch_runtime_lib_path"
                  fi
                fi

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

                unset __torch_runtime_lib_path __cuda_driver_path __candidate
              fi

              echo "Python CUDA development shell"
              python --version

              if [ ! -d .venv ]; then
                uv venv
              fi

              source .venv/bin/activate
            '';
          };
        };
      }
    );
}
