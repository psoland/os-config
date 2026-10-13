{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    neovim

    # Snacks images; Mermaid previews use Merman's browser-free text renderer.
    imagemagick
    (pkgs.callPackage ../../../packages/merman.nix { })

    unzip
    wget
    statix
    nil
    nixfmt
    ruff
    ty
    typescript
    vtsls
    vscode-langservers-extracted
    prettier
    xdg-utils
  ];

  home.sessionVariables.EDITOR = "nvim";

  programs.zsh.shellAliases = {
    vi = "nvim";
    vim = "nvim";
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/config/nvim";
}
