{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.1.21";
  platforms = {
    aarch64-linux = {
      target = "linux-aarch64";
      hash = "sha256-6ESiv6tIoiYJdnnQdryDBC/lf8zvU4fvgC5bJOeLUpo=";
    };
    x86_64-linux = {
      target = "linux-x86_64";
      hash = "sha256-eEJHVcEKQN3jigvbVcIKwZcG6a4F7Wj8Ks8fz/DZQcE=";
    };
    aarch64-darwin = {
      target = "macos-aarch64";
      hash = "sha256-GrON2ScPY6j3lNbWDocC6w0chacr2oXXNeXupD8F/+0=";
    };
  };
  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "herdr-core is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/herdr-core-${platform.target}.tar.gz";
    inherit (platform) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # Linux releases are static. Preserve the signed macOS bundle and executable
  # byte-for-byte instead of stripping, patching, or ad-hoc re-signing them.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/licenses/herdr-core"
    ${
      if stdenvNoCC.hostPlatform.isDarwin then
        ''
          mkdir -p "$out/Applications"
          cp -R "Herdr Core.app" "$out/Applications/"
          ln -s "../Applications/Herdr Core.app/Contents/MacOS/herdr-core" "$out/bin/herdr-core"
        ''
      else
        ''
          install -m755 herdr-core "$out/bin/herdr-core"
        ''
    }
    ln -s herdr-core "$out/bin/hc"
    install -m644 LICENSE THIRD-PARTY-NOTICES "$out/share/licenses/herdr-core/"
    runHook postInstall
  '';

  meta = {
    description = "Persistent terminal runtime for Herdr desktop and mobile clients";
    homepage = "https://herdr.dev/core/";
    license = lib.licenses.asl20;
    mainProgram = "hc";
    platforms = builtins.attrNames platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
