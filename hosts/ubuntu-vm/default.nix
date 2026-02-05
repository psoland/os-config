# Ubuntu VM host configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/home
  ];

  # Host-specific settings for Ubuntu VM
  # Override any module defaults here

  # Example: Override git user settings
  # programs.git.userName = "Your Name";
  # programs.git.userEmail = "your.email@example.com";

  # Host-specific packages (in addition to common packages)
  home.packages = with pkgs; [
    # Add any Ubuntu-VM-specific packages here
    # e.g., cloud-specific CLI tools
  ];

  # Allow home-manager to manage itself
  programs.home-manager.enable = true;
}
