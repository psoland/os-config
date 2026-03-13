{ pkgs, ... }:

{

  imports = [
    ../../modules/common.nix
  ]; 

  home.stateVersion= "25.11";

  home.packages = with pkgs; [
    dockerCompose
  ];

}
