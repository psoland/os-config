# Development tools (lazygit, lazydocker, opencode, devpod, etc.)
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Lazy* family of tools
    lazygit
    lazydocker
    lazysql

    # AI coding assistant
    opencode

    # Remote development environments
    devpod

    # Additional dev tools
    gh           # GitHub CLI
    glab         # GitLab CLI

    # Container tools (complement system Docker)
    dive         # Explore docker images
    ctop         # Container metrics

    # HTTP/API tools
    httpie       # Modern curl alternative
    xh           # Even faster httpie
    curlie       # Curl with httpie interface

    # JSON/YAML tools (in addition to jq/yq from default.nix)
    fx           # Interactive JSON viewer
    gron         # Make JSON greppable

    # Database tools
    usql         # Universal SQL CLI

    # Process management
    process-compose  # Like docker-compose but for processes

    # File transfer
    croc         # Simple file transfer
    rsync

    # Network tools
    bandwhich    # Bandwidth utilization monitor
    gping        # Ping with graph

    # System info
    neofetch     # System info
    ncdu         # Disk usage analyzer

    # Misc dev tools
    just         # Command runner (like make but better)
    watchexec    # Execute commands on file changes
    entr         # Run commands when files change
    tokei        # Code statistics
    hyperfine    # Benchmarking tool
    difftastic   # Structural diff
  ];

  # Lazygit configuration
  xdg.configFile."lazygit/config.yml".text = ''
    gui:
      theme:
        activeBorderColor:
          - "#89b4fa"  # Catppuccin blue
          - bold
        inactiveBorderColor:
          - "#45475a"  # Catppuccin surface1
        searchingActiveBorderColor:
          - "#f9e2af"  # Catppuccin yellow
          - bold
        optionsTextColor:
          - "#89b4fa"  # Catppuccin blue
        selectedLineBgColor:
          - "#313244"  # Catppuccin surface0
        selectedRangeBgColor:
          - "#313244"
        cherryPickedCommitBgColor:
          - "#45475a"
        cherryPickedCommitFgColor:
          - "#89b4fa"
        unstagedChangesColor:
          - "#f38ba8"  # Catppuccin red
        defaultFgColor:
          - "#cdd6f4"  # Catppuccin text
      showRandomTip: false
      showCommandLog: false
      nerdFontsVersion: "3"

    git:
      paging:
        colorArg: always
        pager: delta --dark --paging=never

    os:
      editPreset: "nvim"

    keybinding:
      universal:
        quit: "q"
        return: "<esc>"
  '';

  # Lazydocker configuration
  xdg.configFile."lazydocker/config.yml".text = ''
    gui:
      theme:
        activeBorderColor:
          - "#89b4fa"
          - bold
        inactiveBorderColor:
          - "#45475a"

    commandTemplates:
      dockerCompose: "docker compose"

    oS:
      openCommand: "xdg-open {{filename}}"
  '';

  # Just configuration (justfile syntax highlighting in bat)
  programs.bat = {
    enable = true;
    config = {
      theme = "Catppuccin-mocha";
      style = "numbers,changes,header";
    };
    themes = {
      Catppuccin-mocha = {
        src = pkgs.fetchFromGitHub {
          owner = "catppuccin";
          repo = "bat";
          rev = "d714cc1";
          sha256 = "sha256-Q5B4NDrfCIK3UAMs94vdXnR42k4AXCqZz6sRn8bzmf4=";
        };
        file = "themes/Catppuccin Mocha.tmTheme";
      };
    };
  };
}
