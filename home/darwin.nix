# home/darwin.nix
# macOS-specific home-manager configuration
# Imports common.nix and adds macOS-specific settings

{ config, pkgs, ... }:

{
  # Import common configuration
  imports = [
    ./common.nix
  ];
  
  # macOS-specific home configuration
  # The username and homeDirectory will be set in host-specific configs
  
  # macOS-specific session variables
  home.sessionVariables = {
    # Add macOS-specific environment variables here if needed
  };
  
  # Enable XDG directories on macOS
  xdg.enable = true;
}
