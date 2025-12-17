# hosts/macbook/darwin.nix
# nix-darwin system configuration for macOS
# This manages system-level configuration and integrates with home-manager

{ config, pkgs, ... }:

{
  # System packages that should be installed at the system level
  environment.systemPackages = with pkgs; [
    # Add system-wide packages here if needed
  ];
  
  # Enable the Nix daemon
  services.nix-daemon.enable = true;
  
  # Nix configuration
  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      # Optimize storage
      auto-optimise-store = true;
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      interval = { Weekday = 7; };  # Run weekly
      options = "--delete-older-than 30d";
    };
  };
  
  # macOS system defaults
  # Uncomment and customize as needed
  # system.defaults = {
  #   # Dock settings
  #   dock = {
  #     autohide = true;
  #     orientation = "bottom";
  #     tilesize = 48;
  #     minimize-to-application = true;
  #     show-recents = false;
  #   };
  #   
  #   # Finder settings
  #   finder = {
  #     AppleShowAllExtensions = true;
  #     ShowPathbar = true;
  #     FXEnableExtensionChangeWarning = false;
  #     FXPreferredViewStyle = "Nlsv";  # List view
  #   };
  #   
  #   # Global macOS settings
  #   NSGlobalDomain = {
  #     AppleShowAllExtensions = true;
  #     InitialKeyRepeat = 15;
  #     KeyRepeat = 2;
  #     "com.apple.mouse.tapBehavior" = 1;  # Tap to click
  #     "com.apple.sound.beep.feedback" = 0;  # Disable feedback sound
  #   };
  #   
  #   # Trackpad settings
  #   trackpad = {
  #     Clicking = true;
  #     TrackpadThreeFingerDrag = true;
  #   };
  # };
  
  # Homebrew configuration (for GUI apps not in nixpkgs)
  # Uncomment to enable Homebrew management via nix-darwin
  # homebrew = {
  #   enable = true;
  #   
  #   # Automatically update Homebrew and packages
  #   onActivation = {
  #     autoUpdate = true;
  #     upgrade = true;
  #     cleanup = "zap";
  #   };
  #   
  #   # GUI applications
  #   casks = [
  #     # "visual-studio-code"
  #     # "firefox"
  #     # "docker"
  #     # "iterm2"
  #     # "spotify"
  #   ];
  #   
  #   # Mac App Store apps (requires mas CLI)
  #   masApps = {
  #     # "App Name" = appId;
  #     # Example: "1Password" = 1333542190;
  #   };
  #   
  #   # Homebrew taps
  #   taps = [
  #     # "homebrew/cask-fonts"
  #   ];
  # };
  
  # Create user account
  users.users.psoland = {
    name = "psoland";
    home = "/Users/psoland";
  };
  
  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
