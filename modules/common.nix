# modules/common.nix
{ pkgs, ... }:

{
  
  imports = [
    ./tmux.nix
    ./zsh.nix
    ./starship.nix
    ./nvim.nix
  ];

  home.file.".terminfo".source = "${pkgs.ghostty.terminfo}/share/terminfo";

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
    claude-code
    syncthing
    bitwarden-cli
    gh

    nodejs

    #code-server
    #lazyvim

    # Fetch and apply changes
    (writeShellScriptBin "syncapply" ''
      set -euo pipefail
      cd "$HOME/.dotfiles"
      git pull --rebase

      flake="''${HOME_MANAGER_FLAKE:-}"
      if [ -z "$flake" ] && [ -f "$HOME/.dotfiles/.hm-flake" ]; then
        flake="$(tr -d '\n' < "$HOME/.dotfiles/.hm-flake")"
      fi
      if [ -z "$flake" ]; then
        arch="$(uname -m)"
        case "$arch" in
          aarch64|arm64) flake="psoland-vm-arm" ;;
          *) flake="psoland-vm" ;;
        esac
      fi

      nix build ".#homeConfigurations.''${flake}.activationPackage"
      ./result/activate
    '')

    # Apply changes
    (writeShellScriptBin "apply" ''
      set -euo pipefail
      cd "$HOME/.dotfiles"

      git add .

      flake="''${HOME_MANAGER_FLAKE:-}"
      if [ -z "$flake" ] && [ -f "$HOME/.dotfiles/.hm-flake" ]; then
        flake="$(tr -d '\n' < "$HOME/.dotfiles/.hm-flake")"
      fi
      if [ -z "$flake" ]; then
        arch="$(uname -m)"
        case "$arch" in
          aarch64|arm64) flake="psoland-vm-arm" ;;
          *) flake="psoland-vm" ;;
        esac
      fi

      nix build ".#homeConfigurations.''${flake}.activationPackage"
      ./result/activate
    '')

    # Tmux developer layout
    (writeShellScriptBin "tdl" (builtins.readFile ./tdl.sh))

    # Pi-coding-agent
    (writeShellScriptBin "pi" ''
    exec ${nodejs}/bin/npx -y @mariozechner/pi-coding-agent@latest "$@"
    '')
  ];

  # Configs from config folder
  xdg.configFile."opencode/opencode.json".source = ../config/opencode/opencode.json;
  xdg.configFile."opencode/tui.json".source = ../config/opencode/tui.json;
  
  # Other configs
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;

    config = {
        global = {
            hide_env_diff = true;
          };
      };
  };

  # Hiding logs in direnv
  home.sessionVariables = {
      DIRENV_LOG_FORMAT = "";
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
