{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    neovim

    unzip
    wget
    statix
    nil
    nixpkgs-fmt
    ruff
    ty
    typescript
    vtsls
    vscode-langservers-extracted
    eslint
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
