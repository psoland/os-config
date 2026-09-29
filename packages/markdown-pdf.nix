{
  liberation_ttf,
  pandoc,
  symlinkJoin,
  typst,
  writeShellApplication,
}:

let
  markdown-pdf = writeShellApplication {
    name = "markdown-pdf";
    runtimeInputs = [
      pandoc
      typst
    ];
    text = ''
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -f "$1" ]; then
        echo "Usage: pdf <input.md> [output.pdf]" >&2
        exit 1
      fi

      caller_dir=$(pwd -P)
      input_dir=$(cd "$(dirname "$1")" && pwd -P)
      input=$(basename "$1")
      if [ "$#" -eq 2 ]; then
        output=$2
        case "$output" in
          /*) ;;
          *) output="$caller_dir/$output" ;;
        esac
      else
        output="$input_dir/''${input%.*}.pdf"
      fi

      export MARKDOWN_PDF_INPUT_DIR="$input_dir"
      export MARKDOWN_PDF_CALLER_DIR="$caller_dir"
      unset MARKDOWN_PDF_ASSETS_DIR
      export TYPST_FONT_PATHS="${liberation_ttf}/share/fonts/truetype''${TYPST_FONT_PATHS:+:$TYPST_FONT_PATHS}"

      cd "$input_dir"
      pandoc "$input" \
        --from markdown \
        --to typst \
        --variable mainfont="Liberation Serif" \
        --resource-path "$input_dir:$caller_dir" \
        --lua-filter ${./pdf/resolve-images.lua} \
        --pdf-engine typst \
        --pdf-engine-opt=--root=/ \
        --output "$output"
    '';
  };
in
symlinkJoin {
  name = "markdown-pdf";
  paths = [ markdown-pdf ];
  postBuild = ''
    ln -s markdown-pdf "$out/bin/pdf"
  '';
  meta.mainProgram = "pdf";
}
