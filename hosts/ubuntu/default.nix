# hosts/ubuntu/default.nix
# Ubuntu host configuration
# This is the entry point for Ubuntu systems

{ config, pkgs, ... }:

{
  imports = [
    ../../home/linux.nix
    ./packages.nix
  ];
  
  # User configuration
  home = {
    username = "psoland";
    homeDirectory = "/home/psoland";
  };
}
