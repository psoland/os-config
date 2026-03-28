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
