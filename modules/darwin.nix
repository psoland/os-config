# modules/darwin.nix
# nix-darwin system module for Apple Silicon Macs. Imported only by
# darwinConfigurations entries in flake.nix — never by Home Manager
# host modules, since nix-darwin options are not valid HM options.
#
# This module is opt-in: a darwin host pulls it in via
#   modules = [ ./modules/darwin.nix ... ];
# in flake.nix. Personal Macs that stay on Home Manager only do not
# import it and therefore get no system-level changes (no cask/mas
# installs, no system defaults).
{ username, ... }:

{

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  # stateVersion: forward-compat marker for nix-darwin migrations.
  system.stateVersion = 6;

  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  system.defaults.dock.autohide = true;

  homebrew.enable = true;
  homebrew.casks = [ "raycast" ];
  homebrew.masApps = {
    "Microsoft Outlook" = 985367838;
  };
}
