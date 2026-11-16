# Run without activating Home Manager or starting a relay:
# nix build --impure --no-link --file tests/spark/browse.nix
let
  flake = builtins.getFlake ("path:" + toString ../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-linux;
  inherit (pkgs) lib;
  spark = flake.homeConfigurations.spark.config;
  base = ../../config/opencode/opencode.json;
  browse = lib.findFirst (p: (p.pname or "") == "browse") null spark.home.packages;
  otherHosts = builtins.attrValues (builtins.removeAttrs flake.homeConfigurations [ "spark" ]);
  python = pkgs.python3.withPackages (ps: [ ps.json5 ]);
in
assert browse != null;
assert lib.all (
  host:
  !(lib.any (p: (p.pname or "") == "browse") host.config.home.packages)
  &&
    builtins.readFile host.config.xdg.configFile."opencode/opencode.json".source
    == builtins.readFile base
) otherHosts;
pkgs.runCommand "browse-spark-check" { nativeBuildInputs = [ python ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  python - <<'PY'
  import json
  import subprocess
  from pathlib import Path
  import json5

  with open("${base}") as source:
      expected = json5.load(source)
  with open("${spark.xdg.configFile."opencode/opencode.json".source}") as source:
      actual = json.load(source)

  expected.setdefault("mcp", {}).setdefault("servers", {})["browse"] = {
      "type": "local",
      "command": ["${browse}/bin/browse", "mcp"],
  }
  assert actual == expected, "Browse must preserve all unrelated OpenCode settings"
  assert subprocess.check_output(
      ["${browse}/bin/browse", "--version"], text=True
  ).strip() == "${browse.version}"
  wrapper = Path("${browse}/bin/browse").read_text()
  assert "export OPENCODE_BROWSER_AUTO_UPDATE='off'" in wrapper
  assert "${lib.getBin pkgs.ffmpeg}/bin" in wrapper
  PY
  touch "$out"
''
