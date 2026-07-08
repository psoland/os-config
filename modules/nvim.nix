{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    neovim

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
