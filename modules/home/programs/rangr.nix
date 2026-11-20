{ pkgs, ... }:

{
  # Install only the helper. Rangr owns its writable app, CLI link, and settings;
  # the common profile already puts ~/.local/bin on PATH.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "rangr-install";
      runtimeInputs = with pkgs; [
        gh
        coreutils
        bash
      ];
      text = builtins.readFile ../../../hosts/mac/install-rangr.sh;
      meta.platforms = [ "aarch64-darwin" ];
    })
  ];
}
