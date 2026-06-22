{ pkgs, ... }:

{
  packages = with pkgs; [
    nodejs_24
    pnpm
    typescript
    vtsls
    prettier
    just
  ];

  enterShell = ''
    echo "TypeScript development shell"
    node --version
    pnpm --version
  '';
}
