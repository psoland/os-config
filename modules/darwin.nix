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
      "google-chrome"
      #"logi-options+"
      #"visual-studio-code"
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

    CustomUserPreferences = {
      NSGlobalDomain = {
        NSUserKeyEquivalents = {
          "Bottom" = "nil";
          "Bottom & Quarters" = "nil";
          "Bottom & Top" = "nil";
          "Center" = "nil";
          "Fill" = "nil";
          "Left" = "nil";
          "Left & Quarters" = "nil";
          "Left & Right" = "nil";
          "Minimize" = "@m";
          "Return to Previous Size" = "nil";
          "Right" = "nil";
          "Right & Left" = "nil";
          "Right & Quarters" = "nil";
          "Top" = "nil";
          "Top & Bottom" = "nil";
          "Top & Quarters" = "nil";
        };
      };

      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Mission Control, Application Windows, Spaces, Dock, and desktop switching shortcuts.
          "32".enabled = false;
          "33".enabled = false;
          "52".enabled = false;
          "79".enabled = false;
          "81".enabled = false;
          "118".enabled = false;
          "119".enabled = false;
          "120".enabled = false;
          "121".enabled = false;
          "122".enabled = false;
          "123".enabled = false;
          "124".enabled = false;
          "125".enabled = false;
          "126".enabled = false;
          "127".enabled = false;
          "128".enabled = false;
          "129".enabled = false;
          "130".enabled = false;
          "131".enabled = false;
          "132".enabled = false;
          "133".enabled = false;
          "134".enabled = false;
          "135".enabled = false;
          "136".enabled = false;
          "137".enabled = false;
          "138".enabled = false;
          "139".enabled = false;
          "140".enabled = false;
          "141".enabled = false;
          "142".enabled = false;
          "143".enabled = false;
          "144".enabled = false;
          "145".enabled = false;
          "146".enabled = false;
          "147".enabled = false;
          "148".enabled = false;
          "149".enabled = false;
        };
      };
    };
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  system.defaults.hitoolbox.AppleFnUsageType = "Do Nothing";
}
