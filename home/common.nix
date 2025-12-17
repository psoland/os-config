# home/common.nix
# Common home-manager configuration shared across all platforms
# This is imported by both linux.nix and darwin.nix

{ config, pkgs, ... }:

{
  # Import all common modules
  imports = [
    ../modules/shell.nix
    ../modules/git.nix
    ../modules/starship.nix
    ../modules/packages.nix
  ];
  
  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
  
  # Home Manager state version
  # This value determines the Home Manager release which your configuration is
  # compatible with. You should not change this value, even if you update Home Manager.
  home.stateVersion = "24.05";
  
  # Basic session variables that work across all platforms
  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
