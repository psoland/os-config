# hosts/spark/packages.nix
# Spark OS-specific packages
# These extend the common package list

{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  home.packages = with pkgs; [
    # Add Spark OS-specific packages here
    # Spark OS is Ubuntu-based, so most packages will be similar
    
    # To use unstable versions of packages, use:
    # pkgs-unstable.packageName
  ];
}
