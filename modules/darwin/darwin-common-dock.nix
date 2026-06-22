{ config, ... }:

let
  primaryUser = config.system.primaryUser;
in
{
  system.defaults.dock = {
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
      "/Users/${primaryUser}/Downloads"
    ];
  };
}
