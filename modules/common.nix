# modules/common.nix
{ pkgs, ... }:

{
  
  imports = [
    ./tmux.nix
    ./zsh.nix
    ./starship.nix
  ];

  # Packages that should be installed in all systems
  home.packages = with pkgs; [
    mosh
    htop
    fastfetch
    ripgrep
    gcc
    fd
    jq
    lazygit
    lazysql
    lazydocker
    devpod
    opencode
    syncthing
    bitwarden-cli
    gh
    #code-server
    #lazyvim
    (writeShellScriptBin "tdl" (builtins.readFile ./tdl.sh))
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # Neovim setup (You can install LazyVim normally in ~/.config/nvim)
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Git setup
  programs.git = {
    enable = true;
    settings = {
      user.name = "Petter Søland";
      user.email = "petter.soland@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.default = "current";
      credential.helper = "!${pkgs.gh}/bin/gh auth git-credential";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
  };

  # Start syncthing
  services.syncthing = {
    enable = true;
  };

  # Home Manager needs to be able to update itself
  programs.home-manager.enable = true;
}
