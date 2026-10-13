{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  esbuild,
  nodejs,
  makeWrapper,
}:

let
  revision = "044d8b7d2e5dceef7adc6e620e53e70707b88951";
  upstream = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    rev = revision;
    hash = "sha256-f1xfxIqWKvVCMgdBUt589UgfVCKxkARIeppDCyXQkQk=";
  };
in
buildNpmPackage {
  pname = "merman-nvim";
  version = "0.1.0-${builtins.substring 0 7 revision}";
  src = ./merman;
  npmDepsHash = "sha256-u1hsRPJl2JeQcsmYiqfXSdKL2t6il9ZEaq8Ckor+Icw=";
  nativeBuildInputs = [
    esbuild
    makeWrapper
  ];
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    cp -r ${upstream}/packages/merman/src upstream
    mkdir -p dist
    esbuild render.ts --bundle --platform=node --format=esm \
      --alias:@opentui/core=./opentui.ts --outfile=dist/render.mjs
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node render.test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 dist/render.mjs "$out/lib/merman-nvim/render.mjs"
    install -Dm644 ${upstream}/LICENSE "$out/share/licenses/merman-nvim/LICENSE"
    install -Dm644 LICENSE.opentui "$out/share/licenses/merman-nvim/LICENSE.opentui"
    for license in node_modules/*/{LICENSE,license,LICENSE.md}; do
      if [ -f "$license" ]; then
        install -Dm644 "$license" "$out/share/licenses/merman-nvim/$license"
      fi
    done
    makeWrapper ${lib.getExe nodejs} "$out/bin/merman-nvim" \
      --add-flags "$out/lib/merman-nvim/render.mjs"
    runHook postInstall
  '';

  meta = {
    description = "OpenCode Merman Unicode diagram renderer for Neovim";
    homepage = "https://github.com/anomalyco/opencode/tree/${revision}/packages/merman";
    license = lib.licenses.mit;
    mainProgram = "merman-nvim";
    platforms = lib.platforms.unix;
  };
}
