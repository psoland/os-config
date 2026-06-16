{ username, ... }:

{

  imports = [
    ../../modules/common.nix
  ];

  home = {
    username = username;
    homeDirectory = "/Users/${username}";
    stateVersion = "25.11";
    enableNixpkgsReleaseCheck = false;
  };

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
