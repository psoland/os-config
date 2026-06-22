{ pkgs, ... }:

{
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_24;
    pnpm.enable = true;
  };

  languages.typescript = {
    enable = true;
    lsp.package = pkgs.vtsls;
  };

  packages = with pkgs; [
    prettier
    just
  ];

  enterShell = ''
    echo "TypeScript development shell"
    node --version
    pnpm --version
  '';
}
