# modules/shell.nix
# Zsh shell configuration
# Provides a minimal but functional zsh setup

{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    
    # Enable useful zsh features
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # History configuration
    history = {
      size = 10000;
      save = 10000;
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      share = true;
    };
    
    # Basic shell aliases
    shellAliases = {
      ll = "ls -lah";
      ".." = "cd ..";
      "..." = "cd ../..";
    };
    
    # Additional shell initialization
    initExtra = ''
      # Enable starship prompt
      eval "$(starship init zsh)"
      
      # Set keybindings to emacs mode
      bindkey -e
    '';
  };
}
