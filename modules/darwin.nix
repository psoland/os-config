# modules/darwin.nix
# macOS-specific Home Manager configuration.
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

  targets.darwin.defaults."com.apple.dock".autohide = true;
}
