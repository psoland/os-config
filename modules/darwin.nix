# modules/darwin.nix
# nix-darwin module — macOS system-level configuration.
{ ... }:

{
  nix.enable = false;
  system.stateVersion = 7;
  system.primaryUser = "pettersoland";

  homebrew = {
    enable = true;
    brews = [ "mas" ];
    casks = [
      "raycast"
      "ghostty"
      "obsidian"
      "slack"
      "spotify"
      "microsoft-teams"
    ];
    masApps = {
      "Amphetamine" = 937984704;
      "Bitwarden" = 1352778147;
      "Microsoft Outlook" = 985367838;
      "Microsoft Excel" = 462058435;
      "Microsoft Word" = 462054704;
      "Microsoft PowerPoint" = 462062816;
      "Tailscale" = 1475387142;
    };
  };

  system.defaults.dock.autohide = true;
}
