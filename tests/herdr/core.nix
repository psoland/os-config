# nix build --impure --no-link --file tests/herdr/core.nix
let
  flake = builtins.getFlake ("path:" + toString ../..);
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  core = pkgs.callPackage ../../packages/herdr-core.nix { };
  nativeHome =
    (
      if pkgs.stdenv.hostPlatform.isDarwin then
        flake.homeConfigurations.psoland-mac
      else
        flake.homeConfigurations.spark
    ).config;
  homes = builtins.map (h: h.config) (builtins.attrValues flake.homeConfigurations) ++ [
    flake.darwinConfigurations.pettersoland-mac.config.home-manager.users.pettersoland
  ];
  configured =
    home:
    builtins.length (lib.filter (p: (p.pname or "") == "herdr-core") home.home.packages) == 1
    && home.home.file.".local/bin/herdr-core".source == home.home.file.".local/bin/hc".source
    && !home.home.file.".local/bin/herdr-core".force
    && !home.home.file.".local/bin/hc".force;
  mac = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin.callPackage ../../packages/herdr-core.nix {
    fetchurl = pkgs.fetchurl;
  };
in
assert lib.all configured homes;
assert core.version == "0.1.21";
assert mac.dontFixup;
assert lib.elem "aarch64-darwin" core.meta.platforms;
pkgs.runCommand "herdr-core-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONDONTWRITEBYTECODE=1
  test "$(${core}/bin/herdr-core --version)" = 'hc ${core.version}'
  test "$(${core}/bin/hc --version)" = 'hc ${core.version}'
  python ${./core-smoke.py} \
    --core ${core}/bin/herdr-core \
    --launcher ${nativeHome.home.file.".local/bin/herdr-core".source} \
    --profile-bin ${lib.escapeShellArg "${nativeHome.home.profileDirectory}/bin"} \
    --shell ${pkgs.runtimeShell}
  python - <<'PY'
  import plistlib
  import struct
  import tarfile
  with tarfile.open("${mac.src}", "r:gz") as archive:
      binary = archive.extractfile("Herdr Core.app/Contents/MacOS/herdr-core")
      magic, cpu = struct.unpack("<II", binary.read(8))
      assert magic == 0xfeedfacf and cpu == 0x0100000c
      info = plistlib.load(archive.extractfile("Herdr Core.app/Contents/Info.plist"))
      assert info["CFBundleIdentifier"] == "dev.herdr.core"
      assert "Herdr Core.app/Contents/_CodeSignature/CodeResources" in archive.getnames()
  PY
  touch "$out"
''
