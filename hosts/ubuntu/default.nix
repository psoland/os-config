{ pkgs, ... }:

{

  imports = [
    ../../modules/common.nix
  ]; 

  home.username = "psoland";
  home.homeDirectory = "/home/psoland";
  home.stateVersion= = "25.11"

  home.packages = with pkgs;[
    dockerCompose
  ]

}
