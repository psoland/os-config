# modules/common.nix
{ pkgs, ... }:

{
  # Packages that should be installed in all systems
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

  # Git setup
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

  # Zsh setp
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

  # Home Manager needs to be able to update itself
  programs.home-manager.enable = true;
}
