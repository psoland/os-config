# nix build --impure --no-link --file tests/herdr/default.nix
let
  flake = builtins.getFlake ("path:" + toString ../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  home = flake.homeConfigurations.spark.config;
  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  source = ../..;
in
assert
  builtins.readFile home.xdg.configFile."herdr/config.toml".source
  == builtins.readFile ../../config/herdr/config.toml;
assert
  toString home.home.file.".pi/agent/extensions/herdr-agent-state.ts".source
  == "${flake.inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
assert home.home.file.".claude/hooks/herdr-agent-state.sh".executable;
assert home.home.file.".codex/herdr-agent-state.sh".executable;
assert
  builtins.readFile home.home.file.".claude/hooks/herdr-agent-state.sh".source
  == builtins.readFile "${flake.inputs.herdr}/src/integration/assets/claude/herdr-agent-state.sh";
assert
  builtins.readFile home.home.file.".codex/herdr-agent-state.sh".source
  == builtins.readFile "${flake.inputs.herdr}/src/integration/assets/codex/herdr-agent-state.sh";
assert home.home.activation.herdrAdoptIntegrations.after == [ "writeBoundary" ];
assert home.home.activation.herdrAdoptIntegrations.before == [ "linkGeneration" ];
pkgs.runCommand "herdr-dotfiles-check"
  {
    nativeBuildInputs = [
      python
      pkgs.nodejs
    ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    python ${source}/tests/herdr/test_integrations.py
    node --test ${source}/tests/opencode/herdr-agent.test.mjs
    python - <<'PY'
    import tomlkit
    from pathlib import Path
    config = tomlkit.parse(Path("${source}/config/herdr/config.toml").read_text())
    assert config["keys"]["prefix"] == "ctrl+s"
    assert config["keys"]["previous_tab"] == ["prefix+p", "prefix+ctrl+p"]
    assert config["keys"]["next_tab"] == ["prefix+n", "prefix+ctrl+n"]
    assert config["ui"]["prompt_new_tab_name"] is False
    assert set(config["keys"]) == {"prefix", "previous_tab", "next_tab"}
    PY
    touch "$out"
  ''
