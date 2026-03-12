# modules/common.nix
{ pkgs, ... }:

{
  # Pakker du ALLTID vil ha, på tvers av alle operativsystemer
  home.packages = with pkgs;[
    mosh
    htop
    fastfetch
    tmux
    ripgrep
    jq
    lazygit
    lazyvim
    lazysql
    devpod
    opencode
    syncthing
  ];

  # Git-oppsettet ditt er likt overalt
  programs.git = {
    enable = true;
    userName = "Petter Søland";
    userEmail = "petter.soland@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.default = "current"
    };
  };

  # Zsh-oppsettet ditt
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -la";
    };

    #oh-my-zsh = {
    #  enable = true;
    #  plugins =[ "git" "docker" "sudo" ];
    #  theme = "robbyrussell";
    #};
  };

  # Home Manager må alltid kunne oppdatere seg selv
  programs.home-manager.enable = true;
}
