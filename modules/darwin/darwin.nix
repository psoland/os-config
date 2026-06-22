# modules/darwin/darwin.nix
# nix-darwin module - macOS system-level configuration.
{ ... }:

{
  imports = [
    ./darwin-common-dock.nix
  ];

  nix.enable = false;
  system.stateVersion = 7;

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
