{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "2.0.18";
  platform =
    if stdenvNoCC.hostPlatform.isAarch64 then
      {
        name = "linux-arm64";
        hash = "sha256-3cmOXHicSW2toez66f5OCTHHrEOkbaVDa5fs2lzQul0=";
      }
    else if stdenvNoCC.hostPlatform.isx86_64 then
      {
        name = "linux-x64-baseline";
        hash = "sha256-VItwnvqCKfl8NffMa6Y1QlxAfFszgqdDXpKoDOAGz80=";
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
