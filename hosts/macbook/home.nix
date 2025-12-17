# hosts/macbook/home.nix
# macOS home-manager configuration
# This is used by nix-darwin for home-manager integration

{ config, pkgs, ... }:

{
  imports = [
    ../../home/darwin.nix
    ./packages.nix
  ];
  
  # User configuration
  home = {
    username = "psoland";
    homeDirectory = "/Users/psoland";
  };
}
