{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  glibc,
}:

let
  version = "2.3.0";
  platforms = {
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha256-vjAGY1O7WSxDkZsxBy/0CZ4GljbDGhaAawiHN+AofOo=";
    };
    x86_64-linux = {
      name = "linux-x64-baseline";
      hash = "sha256-76kYeGgVmen9er1y9P2aCznlh0c7Qlb0QQUbQrF0MTk=";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha256-wlJHpyu50MuP7KZ+uV8UF7YcnPsEKQh1b7r41sFwZB4=";
    };
  };
  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "opencode2 is unsupported on ${stdenvNoCC.hostPlatform.system}");
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
  # Preserve the official native executable, including its macOS signature.
  dontStrip = true;
  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ glibc ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode "$out/bin/opencode"
    ln -s opencode "$out/bin/opencode2"
    runHook postInstall
  '';

  meta = {
    description = "OpenCode V2 coding agent";
    homepage = "https://opencode.ai/v2/docs";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
