# modules/starship.nix
# Starship prompt configuration
# A minimal, fast, and customizable prompt for any shell

{ config, lib, ... }:

{
  programs.starship = {
    enable = true;
    
    # Minimal configuration - starship has great defaults
    # You can customize this later by adding settings here
    settings = {
      # Show command execution time if over 500ms
      cmd_duration = {
        min_time = 500;
        format = "took [$duration]($style) ";
      };
      
      # Show nix-shell indicator
      nix_shell = {
        format = "via [$symbol$state]($style) ";
        symbol = "❄️ ";
      };
      
      # Compact directory display
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
    };
  };
}
