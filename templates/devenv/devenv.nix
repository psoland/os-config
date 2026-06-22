{ pkgs, lib, ... }:

let
  pythonRuntimeLibs = lib.optionals pkgs.stdenv.isLinux [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
in
{
  languages.python = {
    enable = true;
    version = "3.12";
    uv.enable = true;
  };

  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_22;
    pnpm.enable = true;
  };

  languages.typescript = {
    enable = true;
    lsp.package = pkgs.vtsls;
  };

  packages =
    (with pkgs; [
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
