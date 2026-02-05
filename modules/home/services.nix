# Services configuration (Syncthing, etc.)
{ config, pkgs, lib, ... }:

{
  # Syncthing - continuous file synchronization
  services.syncthing = {
    enable = true;

    # Syncthing will manage its own config through the GUI
    # This just ensures the service runs
  };

  # Note: After enabling, access Syncthing GUI at http://localhost:8384
  # You'll need to:
  # 1. Set up device ID sharing with other machines
  # 2. Configure folders to sync
  # 3. Optionally set up Syncthing on other devices

  # Additional services can be added here

  # Example: SSH agent
  # services.ssh-agent.enable = true;

  # Example: GPG agent
  # services.gpg-agent = {
  #   enable = true;
  #   enableSshSupport = true;
  #   pinentryPackage = pkgs.pinentry-curses;
  # };
}
