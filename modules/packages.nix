# modules/packages.nix
# Common packages available on all systems
# These are installed from stable nixpkgs by default
# To use unstable versions, override in host-specific packages.nix

{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Core utilities
    git
    curl
    wget
    
    # CLI tools
    tree
    jq
    fzf
    ripgrep
    tmux
    
    # Editor
    neovim
    
    # Prompt
    starship
  ];
}
