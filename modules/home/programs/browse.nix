{ pkgs, lib, ... }:

let
  browse = pkgs.callPackage ../../../packages/browse.nix { };
  python = pkgs.python3.withPackages (ps: [ ps.json5 ]);
  server = pkgs.writeText "browse-mcp.json" (
    builtins.toJSON {
      type = "local";
      command = [
        "${browse}/bin/browse"
        "mcp"
      ];
    }
  );
in
{
  home.packages = [ browse ];

  # Override only this host's shared config symlink. Parse JSONC at build time
  # rather than maintaining a second copy or letting browse install edit it.
  xdg.configFile."opencode/opencode.json".source = lib.mkForce (
    pkgs.runCommand "opencode-with-browse.json" { nativeBuildInputs = [ python ]; } ''
      python - ${../../../config/opencode/opencode.json} ${server} "$out" <<'PY'
      import json
      import sys
      import json5

      with open(sys.argv[1]) as source:
          config = json5.load(source)
      with open(sys.argv[2]) as source:
          server = json.load(source)
      config.setdefault("mcp", {}).setdefault("servers", {})["browse"] = server
      with open(sys.argv[3], "w") as output:
          json.dump(config, output, indent=2)
          output.write("\n")
      PY
    ''
  );
}
