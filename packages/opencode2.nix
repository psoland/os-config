{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.0.0-beta-18684";
  platform =
    if stdenvNoCC.hostPlatform.isAarch64 then
      {
        name = "linux-arm64";
        hash = "sha256-YPImGIn6g5D9KWpRMXq4216vq5AzChScchl7ivnzm1I=";
      }
    else if stdenvNoCC.hostPlatform.isx86_64 then
      {
        name = "linux-x64-baseline";
        hash = "sha256-KkpcAV4LcLuk/O8VF2IU4KCnzBwrrmySxsoA3tO8QHs=";
      }
    else
      throw "opencode2 is unsupported on ${stdenvNoCC.hostPlatform.system}";
in
stdenvNoCC.mkDerivation {
  pname = "opencode2";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/cli-${platform.name}/-/cli-${platform.name}-${version}.tgz";
    inherit (platform) hash;
  };

  sourceRoot = "package";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode2 "$out/bin/opencode2"
    runHook postInstall
  '';

  meta = {
    description = "Beta version of the OpenCode coding agent";
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
