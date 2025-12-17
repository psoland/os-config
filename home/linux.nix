# home/linux.nix
# Linux-specific home-manager configuration
# Imports common.nix and adds Linux-specific settings

{ config, pkgs, ... }:

{
  # Import common configuration
  imports = [
    ./common.nix
  ];
  
  # Linux-specific home configuration
  # The username and homeDirectory will be set in host-specific configs
  
  # Linux-specific session variables
  home.sessionVariables = {
    # Add Linux-specific environment variables here if needed
  };
  
  # Enable XDG directories on Linux
  xdg.enable = true;
}
