# modules/darwin.nix
# Shared nix-darwin system configuration for all Mac hosts.
{ username, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

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
