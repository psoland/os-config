{
  config,
  lib,
  pkgs,
  ...
}:
let
  core = pkgs.callPackage ../../../packages/herdr-core.nix { };
  # The mobile app probes ~/.local/bin even when SSH has not loaded Nix's PATH.
  # Give the core and its future agent processes the Home Manager profile too.
  sshLauncher = pkgs.writeShellScript "herdr-core-ssh" ''
    export PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin:${config.home.homeDirectory}/.local/bin"}:"''${PATH:-/usr/bin:/bin}"
    exec ${core}/bin/herdr-core "$@"
  '';
in
{
  home.packages = [ core ];
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # Do not force these links: an existing manual install must be reviewed first.
  home.file.".local/bin/herdr-core".source = sshLauncher;
  home.file.".local/bin/hc".source = sshLauncher;
}
