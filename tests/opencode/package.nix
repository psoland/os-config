# nix build --impure --no-link --file tests/opencode/package.nix
# Runs the native binary; evaluates every configured host, including both Macs.
let
  flake = builtins.getFlake ("path:" + toString ../..);
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  package = pkgs.callPackage ../../packages/opencode2.nix { };
  mac = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin.callPackage ../../packages/opencode2.nix {
    # Allow checking the official macOS artifact on Linux without a Mac builder.
    fetchurl = pkgs.fetchurl;
  };
  homes = builtins.map (home: home.config) (builtins.attrValues flake.homeConfigurations) ++ [
    flake.darwinConfigurations.pettersoland-mac.config.home-manager.users.pettersoland
  ];
  onlyV2 =
    home:
    builtins.length (lib.filter (p: (p.pname or "") == "opencode2") home.home.packages) == 1
    && !(lib.any (p: (p.pname or "") == "opencode") home.home.packages)
    && home.programs.zsh.shellAliases.oc2 == "opencode2"
    && home.programs.zsh.shellAliases.oc-serve == "opencode serve --port 4091";
in
assert lib.all onlyV2 homes;
assert mac.meta.mainProgram == "opencode";
assert
  mac.src.url == "https://registry.npmjs.org/@opencode/cli-darwin-arm64/-/cli-darwin-arm64-2.3.0.tgz";
assert lib.elem "aarch64-darwin" package.meta.platforms;
pkgs.runCommand "opencode-v2-package-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    test "$(readlink ${package}/bin/opencode2)" = opencode
    test "$(${package}/bin/opencode --version)" = 'opencode v${package.version}'
    test "$(${package}/bin/opencode2 --version)" = 'opencode v${package.version}'
    test "$(${package}/bin/opencode debug paths db)" = "$(${package}/bin/opencode2 debug paths db)"
    bash -n ${../../profiles/home/td.sh} ${../../profiles/home/tdl.sh}
    if grep -F 'opencode --port' ${../../profiles/home/td.sh} ${../../profiles/home/tdl.sh}; then
      echo 'Legacy OpenCode launcher found' >&2
      exit 1
    fi
    python - <<'PY'
    import struct
    import tarfile
    with tarfile.open("${mac.src}", "r:gz") as archive:
        binary = archive.extractfile("package/bin/opencode")
        magic, cpu = struct.unpack("<II", binary.read(8))
        assert magic == 0xfeedfacf, "Expected a 64-bit Mach-O executable"
        assert cpu == 0x0100000c, "Expected Apple Silicon ARM64"
    PY
    touch "$out"
  ''
