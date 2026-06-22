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
}
