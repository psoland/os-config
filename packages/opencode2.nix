{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "2.0.26";
  platform =
    if stdenvNoCC.hostPlatform.isAarch64 then
      {
        name = "linux-arm64";
        hash = "sha256-HXEX27MZaEVviVN7Vi+14g5I2envAyX8iEWr3abvSEI=";
      }
    else if stdenvNoCC.hostPlatform.isx86_64 then
      {
        name = "linux-x64-baseline";
        hash = "sha256-3OMCsw4K2bmGttNq56SD200WNSuqbOwzLI0MfI4Zvxk=";
      }
    else
      throw "opencode2 is unsupported on ${stdenvNoCC.hostPlatform.system}";
in
stdenvNoCC.mkDerivation {
  pname = "opencode2";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/cli-${platform.name}/-/cli-${platform.name}-${version}.tgz";
    inherit (platform) hash;
  };

  sourceRoot = "package";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode "$out/bin/opencode2"
    runHook postInstall
  '';

  meta = {
    description = "OpenCode V2 coding agent";
    homepage = "https://opencode.ai/v2/docs";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
