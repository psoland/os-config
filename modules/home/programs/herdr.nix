{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  assets = "${inputs.herdr}/src/integration/assets";
  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  manage = lib.escapeShellArgs [
    "${python}/bin/python3"
    "${../../../config/herdr/manage-integrations.py}"
    "--home"
    config.home.homeDirectory
    "--config-home"
    config.xdg.configHome
    "--state-home"
    config.xdg.stateHome
    "--declarations"
    "${../../../config/herdr/agent-hooks.json}"
  ];
in
{
  home.packages = [
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr
    # The upstream Claude/Codex scripts look up python3 at runtime.
    pkgs.python3
  ];

  xdg.configFile."herdr/config.toml" = {
    source = ../../../config/herdr/config.toml;
    force = true;
  };
  home.file = {
    ".pi/agent/extensions/herdr-agent-state.ts" = {
      source = "${assets}/pi/herdr-agent-state.ts";
      force = true;
    };
    ".claude/hooks/herdr-agent-state.sh" = {
      source = "${assets}/claude/herdr-agent-state.sh";
      executable = true;
      force = true;
    };
    ".codex/herdr-agent-state.sh" = {
      source = "${assets}/codex/herdr-agent-state.sh";
      executable = true;
      force = true;
    };
  };

  # Forced links bypass collision checks only for these adopted files. Validate
  # and back them up after all read-only checks, before HM replaces any links.
  # Unknown scripts/symlinks abort activation instead of being overwritten.
  home.activation.herdrAdoptIntegrations =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        run ${manage} adopt
      '';

  # These agent-owned config files contain mutable preferences/trust settings.
  # Merge declarative Herdr hooks, not entire machine-specific config files.
  home.activation.herdrAgentHooks = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${manage} configure
  '';
}
