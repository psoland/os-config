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
              export LD_LIBRARY_PATH="${lib.makeLibraryPath torchRuntimeLibs}:''${LD_LIBRARY_PATH:-}"

              if [ "$(uname -s)" = "Linux" ]; then
                __cuda_driver_path=""

                for __ldconfig in /sbin/ldconfig.real /usr/sbin/ldconfig.real /sbin/ldconfig /usr/sbin/ldconfig; do
                  if [ -x "$__ldconfig" ]; then
                    __cuda_driver_path="$($__ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1/ { print $NF; exit }')"
                    if [ -n "$__cuda_driver_path" ]; then
                      break
                    fi
                  fi
                done

                if [ -z "$__cuda_driver_path" ] && command -v ldconfig >/dev/null 2>&1; then
                  __cuda_driver_path="$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1/ { print $NF; exit }')"
                fi

                if [ -z "$__cuda_driver_path" ]; then
                  for __candidate in \
                    /usr/lib/aarch64-linux-gnu/libcuda.so.1 \
                    /lib/aarch64-linux-gnu/libcuda.so.1 \
                    /usr/lib/x86_64-linux-gnu/libcuda.so.1 \
                    /lib/x86_64-linux-gnu/libcuda.so.1 \
                    /usr/lib64/libcuda.so.1 \
                    /lib64/libcuda.so.1 \
                    /run/opengl-driver/lib/libcuda.so.1 \
                    /usr/lib/wsl/lib/libcuda.so.1 \
                    /usr/local/nvidia/lib64/libcuda.so.1
                  do
                    if [ -r "$__candidate" ]; then
                      __cuda_driver_path="$__candidate"
                      break
                    fi
                  done
                fi

                if [ -n "$__cuda_driver_path" ] && [ -r "$__cuda_driver_path" ]; then
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

                unset __cuda_driver_path __candidate __ldconfig
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
