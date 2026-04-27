# modules/darwin.nix
# macOS-specific Home Manager configuration.
{ ... }:

{
  # Keep Homebrew on PATH for login shells.
  # macOS reads /etc/zprofile -> ~/.zprofile for login shells; Home Manager
  # writes ~/.zprofile from programs.zsh.profileExtra. Without this, anything
  # installed under /opt/homebrew (casks, GUI apps' CLIs, etc.) will not be on
  # PATH unless a Nix-installed equivalent shadows it.
  programs.zsh.profileExtra = ''
    # Homebrew (Apple Silicon)
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    # Homebrew (Intel) - harmless on Apple Silicon if not present
    if [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  '';
}
