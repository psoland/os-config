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
      "orbstack"
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
      "Magnet" = 441258766;
    };
  };

  system.defaults = {
    dock = {
      autohide = true;
      magnification = true;
      largesize = 77;
      tilesize = 49;
      "show-recents" = false;
      "wvous-bl-corner" = 4;
      "wvous-br-corner" = 12;

      persistent-apps = [
        "/System/Applications/Calendar.app"
        "/Applications/Slack.app"
        "/Applications/Spotify.app"
        "/Applications/Ghostty.app"
        "/Applications/Obsidian.app"
      ];

      persistent-others = [
        "/Applications"
        "/Users/pettersoland/Downloads"
      ];
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
    };

    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 5;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  system.defaults.hitoolbox.AppleFnUsageType = "Do Nothing";
}
