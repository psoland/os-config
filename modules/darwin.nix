# modules/darwin.nix
# nix-darwin module — macOS system-level configuration.
{ ... }:

{
  homebrew = {
    enable = true;
    brews = [ "mas" ];
    casks = [ "raycast" ];
    masApps = {
      "Microsoft Outlook" = 985367838;
    };
  };

  system.defaults.dock.autohide = true;
}
