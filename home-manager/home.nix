{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Import all modules
  imports = [
    ./modules/shell.nix
    ./modules/tmux.nix
    ./modules/nixvim
    ./modules/dev-tools.nix
    ./modules/services.nix
  ];

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  # Common packages available everywhere
  home.packages = with pkgs; [
    # Core utilities
    coreutils
    findutils
    gnugrep
    gnused
    gawk

    # File utilities
    tree
    file
    unzip
    zip
    gzip

    # Network utilities
    curl
    wget
    htop
    btop

    # Text processing
    jq
    yq

    # Development
    gnumake
    cmake

    # Nix tools
    nil # Nix LSP
    nixfmt-rfc-style
    nix-tree

    # Helpful CLI tools
    ripgrep
    fd
    bat
    eza
    fzf
    zoxide
    delta # Better git diff
    tldr # Simplified man pages
    duf # Disk usage
    dust # du alternative
    procs # ps alternative
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
  };

  # XDG directories
  xdg.enable = true;

  # Git configuration
  programs.git = {
    enable = true;
    userName = "psoland";
    # userEmail will need to be set - placeholder for now
    userEmail = lib.mkDefault "psoland@users.noreply.github.com";

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };

    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      lg = "log --oneline --graph --decorate";
      last = "log -1 HEAD";
      unstage = "reset HEAD --";
    };
  };

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # SSH configuration
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";

    # Example host configurations - customize as needed
    matchBlocks = {
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
          IdentitiesOnly = "yes";
        };
      };
    };
  };

  # GPG for signing
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
