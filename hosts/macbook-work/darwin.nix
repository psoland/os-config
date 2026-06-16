# hosts/macbook-work/darwin.nix
# System-level nix-darwin configuration for the work Mac (pettersoland).
# This module is intentionally separate from modules/darwin.nix (which is a
# Home Manager module shared with the personal Mac) because nix-darwin
# system options must not be evaluated on machines that don't use darwin.
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
