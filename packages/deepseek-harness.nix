{
  lib,
  stdenvNoCC,
  fetchPnpmDeps,
  makeWrapper,
  nodejs_24,
  pnpm_11,
  pnpmConfigHook,
  src,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "deepseek-harness";
  version = "0.1.1-rc.2";

  inherit src;

  DSH_CLIENT_COMMIT_HASH = "b150a55";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-F6hoP3TelUybd0cs/WfK6iakPPun3IaZKM3etkwlvaA=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/deepseek-harness" "$out/bin"
    cp -a . "$out/lib/deepseek-harness"

    # Loader plugins resolve workspace packages from the repository root.
    # pnpm only links those packages through its internal virtual store.
    rm -rf "$out/lib/deepseek-harness/node_modules/@deepseek-ai"
    mkdir "$out/lib/deepseek-harness/node_modules/@deepseek-ai"
    for package in node_modules/.pnpm/node_modules/@deepseek-ai/*; do
      name="$(basename "$package")"
      target="$(readlink "$package")"
      ln -s "$out/lib/deepseek-harness/''${target#../../../../}" \
        "$out/lib/deepseek-harness/node_modules/@deepseek-ai/$name"
    done

    makeWrapper ${nodejs_24}/bin/node "$out/bin/dsh" \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/deepseek-harness/apps/cli/lib/bin.js"

    runHook postInstall
  '';

  meta = {
    description = "Plugin-based agent harness from DeepSeek AI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.unix;
  };
})
