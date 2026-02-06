# User configuration for psoland
# Inspired by ironicbadger's alex.nix and mitchellh's home-manager.nix
{ config, pkgs, lib, ... }:

let
  # Shell aliases (like mitchellh's pattern)
  shellAliases = {
    # Git shortcuts
    ga = "git add";
    gc = "git commit";
    gco = "git checkout";
    gd = "git diff";
    gl = "git log --oneline -20";
    gp = "git push";
    gs = "git status";
    
    # Modern replacements
    cat = "bat";
    ls = "eza";
    ll = "eza -la";
    tree = "eza --tree";
    
    # Navigation
    ".." = "cd ..";
    "..." = "cd ../..";
  };
in {
  # Let home-manager manage itself
  programs.home-manager.enable = true;

  # XDG directories
  xdg.enable = true;

  # Environment variables
  home.sessionVariables = {
    EDITOR = "vim";  # Change to nvim when added
    PAGER = "less -FirSwX";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # Packages (minimal set - per-project tools via devShells)
  home.packages = with pkgs; [
    # Modern CLI essentials
    fd            # Better find
    ripgrep       # Better grep
    jq            # JSON processor
    htop          # Process viewer
    tree          # Directory tree (fallback)
    wget
    curl
    unzip

    # Development
    gh            # GitHub CLI
  ];

  #---------------------------------------------------------------------------
  # Shell: zsh + starship
  #---------------------------------------------------------------------------
  
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    inherit shellAliases;
    
    history = {
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    initExtra = ''
      # Better directory navigation
      setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS

      # Keybindings
      bindkey '^[[A' history-search-backward
      bindkey '^[[B' history-search-forward
    '';
  };

  programs.bash.enable = true;  # Keep as fallback

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = lib.importTOML ./starship/starship.toml;
  };

  #---------------------------------------------------------------------------
  # CLI Tools with shell integration
  #---------------------------------------------------------------------------

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.bat = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  #---------------------------------------------------------------------------
  # Git
  #---------------------------------------------------------------------------

  programs.git = {
    enable = true;
    lfs.enable = true;
    
    userName = "Your Name";  # TODO: Update
    userEmail = "you@example.com";  # TODO: Update
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.default = "current";
      core.editor = "vim";
      
      # Pretty log alias
      alias.prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
    };
  };
}
