{
  corefonts,
  pandoc,
  runCommand,
  typst,
  writeShellApplication,
}:

let
  logo = ./knowit-pdf/KnowitBrand/Logotype/Digital/Still/SVG/Logotype-Knowit-Digital-Black.svg;
  template = runCommand "knowit-template.typst" { } ''
    substitute ${./knowit-pdf/knowit.typst} "$out" --subst-var-by KNOWIT_LOGO ${logo}
  '';
in
writeShellApplication {
  name = "knowit-pdf";
  runtimeInputs = [
    pandoc
    typst
  ];
  text = ''
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -f "$1" ]; then
      echo "Usage: knowit-pdf <input.md> [output.pdf]" >&2
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

    # Preserve any additional font directories configured by the caller.
    export TYPST_FONT_PATHS="${corefonts}/share/fonts/truetype''${TYPST_FONT_PATHS:+:$TYPST_FONT_PATHS}"
    export KNOWIT_PDF_INPUT_DIR="$input_dir"
    export KNOWIT_PDF_CALLER_DIR="$caller_dir"
    export KNOWIT_PDF_ASSETS_DIR="${./knowit-pdf}"

    cd "$input_dir"
    pandoc "$input" \
      --from markdown \
      --to typst \
      --template ${template} \
      --resource-path "$input_dir:$caller_dir:${./knowit-pdf}" \
      --lua-filter ${./knowit-pdf/resolve-images.lua} \
      --pdf-engine typst \
      --pdf-engine-opt=--root=/ \
      --output "$output"
  '';
}
