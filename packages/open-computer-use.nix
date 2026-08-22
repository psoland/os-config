{
  stdenv,
  stdenvNoCC,
  lib,
  fetchurl,
  makeWrapper,
  nodejs,
  python3,
  gobject-introspection,
  at-spi2-core,
  gtk3,
}:

let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
  linuxWrapperArgs = lib.optionals stdenv.hostPlatform.isLinux [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ python ])
    "--prefix"
    "GI_TYPELIB_PATH"
    ":"
    (lib.makeSearchPath "lib/girepository-1.0" [
      gobject-introspection
      at-spi2-core
      gtk3
    ])
  ];
  commands = [
    "open-computer-use"
    "ocu"
    "open-computer-use-mcp"
    "open-codex-computer-use-mcp"
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "open-computer-use";
  version = "0.3.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/open-computer-use/-/open-computer-use-${finalAttrs.version}.tgz";
    hash = "sha512-q8gsh6Pqme7qiiLiDXWdsr6xs8TTO0zRaW1e8nEIigEg8uwBurPFp8CWbq8mPuLWxk+5lQqk2Tdq9iICj82WZQ==";
  };

  sourceRoot = "package";
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  # The npm archive contains a signed macOS app bundle.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/open-computer-use" "$out/bin"
    cp -R . "$out/lib/open-computer-use"

    ${lib.concatMapStringsSep "\n" (command: ''
      makeWrapper ${nodejs}/bin/node "$out/bin/${command}" \
        --add-flags "$out/lib/open-computer-use/bin/${command}" \
        ${lib.escapeShellArgs linuxWrapperArgs}
    '') commands}

    runHook postInstall
  '';

  meta = {
    description = "Cross-platform Computer Use MCP server";
    homepage = "https://github.com/iFurySt/open-codex-computer-use";
    license = lib.licenses.mit;
    mainProgram = "open-computer-use";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
})
