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
      # Node.js project
      nodejs_22
      pnpm
      typescript
      vtsls

      # Python project
      python312
      uv
      ruff
      ty

      # Common tools
      just
      watchexec
    ])
    ++ pythonRuntimeLibs;

  enterShell = ''
    if [ -n "${lib.makeLibraryPath pythonRuntimeLibs}" ]; then
      export LD_LIBRARY_PATH="${lib.makeLibraryPath pythonRuntimeLibs}:''${LD_LIBRARY_PATH:-}"
    fi

    echo "Development shell activated!"
  '';
}
