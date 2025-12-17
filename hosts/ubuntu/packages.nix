# hosts/ubuntu/packages.nix
# Ubuntu-specific packages
# These extend the common package list

{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  home.packages = with pkgs; [
    # Add Ubuntu-specific packages here
    # Example: htop, ncdu, etc.
    
    # To use unstable versions of packages, use:
    # pkgs-unstable.packageName
  ];
}
