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
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python312
            uv
            ruff
            ty
            just
          ];

          shellHook = ''
            echo "Python development shell"
            python --version

            if [ ! -d .venv ]; then
              uv venv
            fi

            source .venv/bin/activate
          '';
        };
      }
    );
}
