# Common home-manager configuration
# This module imports all the individual configuration modules
{ config, pkgs, lib, ... }:

{
  imports = [
    ./shell.nix
    ./git.nix
    ./editors.nix
    ./terminal.nix
    ./dev-tools.nix
    ./services.nix
  ];

  # Home Manager needs this
  home.stateVersion = "24.05";

  # Common packages available everywhere
  home.packages = with pkgs; [
    # Core utilities
    coreutils
    findutils
    gnugrep
    gnused
    gawk

    # Modern CLI replacements
    eza        # Better ls
    bat        # Better cat
    fd         # Better find
    ripgrep    # Better grep
    jq         # JSON processor
    yq         # YAML processor
    htop       # Process viewer
    btop       # Even better process viewer
    tree       # Directory tree
    wget
    curl
    unzip
    zip

    # Networking
    dnsutils   # dig, nslookup
    netcat-gnu # nc

    # Development essentials
    gnumake
    gcc
  ];

  # Enable XDG directories
  xdg.enable = true;

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
  };

  # Enable fontconfig for better font handling
  fonts.fontconfig.enable = true;

  # Let Home Manager manage the shell integration
  programs.bash.enable = true;  # Keep bash available as fallback
}
