# hosts/spark/default.nix
# Spark OS host configuration
# This is the entry point for Spark OS systems

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
