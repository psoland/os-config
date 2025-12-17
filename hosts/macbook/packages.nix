# hosts/macbook/packages.nix
# macOS-specific packages
# These extend the common package list

{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  home.packages = with pkgs; [
    # macOS-specific packages
    # Add GNU tools that differ from BSD variants
    coreutils
    
    # To use unstable versions of packages, use:
    # pkgs-unstable.packageName
  ];
}
