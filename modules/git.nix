# modules/git.nix
# Git configuration
# Override userName and userEmail in host-specific configs if needed

{ config, lib, ... }:

{
  programs.git = {
    enable = true;
    
    # User configuration (can be overridden in host configs)
    userName = lib.mkDefault "psoland";
    userEmail = lib.mkDefault "petter.soland@gmail.com";
    
    # Useful aliases
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
    };
    
    # Additional configuration
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "nvim";
    };
  };
}
