{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  ffmpeg,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "browse";
  version = "0.1.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/browse-linux-arm64/-/browse-linux-arm64-${finalAttrs.version}.tgz";
    hash = "sha256-nxcSCg0dekKrTdwqoZ+7m2u/I1e8jXwXUs8Oe5CtIo8=";
  };

  sourceRoot = "package";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  dontBuild = true;
  # Preserve the official native executable.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/browse "$out/libexec/browse"
    install -Dm644 LICENSE "$out/share/licenses/browse/LICENSE"
    # Nix owns CLI updates. The relay inherits this override when started by
    # either the CLI or MCP server; recording tools also need ffmpeg on PATH.
    makeWrapper "$out/libexec/browse" "$out/bin/browse" \
      --set OPENCODE_BROWSER_AUTO_UPDATE off \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/browse" --version)" = "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Browser automation CLI and MCP server for your Chromium browser";
    homepage = "https://github.com/anomalyco/browse";
    license = lib.licenses.mit;
    mainProgram = "browse";
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
