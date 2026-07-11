# Shared Home Manager profile.
{
  pkgs,
  lib,
  inputs,
  ...
}:

{

  imports = [
    ../../modules/home/programs/tmux.nix
    ../../modules/home/programs/zsh.nix
    ../../modules/home/programs/starship.nix
    ../../modules/home/programs/nvim.nix
    inputs.hunk.homeManagerModules.default
  ];

  # Ghostty terminfo: ghostty itself is Linux-only in nixpkgs; on macOS the
  # Ghostty.app bundle ships its own terminfo, so we only need this on Linux.
  home.file.".terminfo" = lib.mkIf pkgs.stdenv.isLinux {
    source = "${pkgs.ghostty.terminfo}/share/terminfo";
  };

  # Packages that should be installed in all systems
  home.packages =
    with pkgs;
    [
      # devenv
      # temp devenv implementation:
      inputs.nixpkgs-devenv-210.legacyPackages.${pkgs.stdenv.hostPlatform.system}.devenv
      mosh
      htop
      fastfetch
      ripgrep
      fd
      jq
      lazygit
      lazydocker
      lazysql
      pgcli
      opencode
      codex
      claude-code
      bitwarden-cli
      gh
      git-lfs
      lsof
      devpod
      cloudflared
      bitwarden-cli
      nodejs
    ]
    # Linux-only: gcc (use Apple clang from Xcode CLT on macOS),
    # syncthing (use the GUI app on macOS), lazysql (pull in Linux deps).
    ++ lib.optionals pkgs.stdenv.isLinux [
      gcc
      syncthing
    ]
    ++ [

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
          echo "No Home Manager target selected. Set HOME_MANAGER_FLAKE or create ~/.dotfiles/.hm-flake." >&2
          exit 1
        fi

        if [ "$(uname -s)" = "Darwin" ]; then
          case "$flake" in
            pettersoland-mac)
              nix build ".#darwinConfigurations.$flake.system"
              sudo ./result/activate
              ;;
            *)
              nix build ".#homeConfigurations.$flake.activationPackage"
              ./result/activate
              ;;
          esac
        else
          nix build ".#homeConfigurations.$flake.activationPackage"
          ./result/activate
        fi
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
          echo "No Home Manager target selected. Set HOME_MANAGER_FLAKE or create ~/.dotfiles/.hm-flake." >&2
          exit 1
        fi

        if [ "$(uname -s)" = "Darwin" ]; then
          case "$flake" in
            pettersoland-mac)
              nix build ".#darwinConfigurations.$flake.system"
              sudo ./result/activate
              ;;
            *)
              nix build ".#homeConfigurations.$flake.activationPackage"
              ./result/activate
              ;;
          esac
        else
          nix build ".#homeConfigurations.$flake.activationPackage"
          ./result/activate
        fi
      '')

      # Tmux developer layouts
      (writeShellScriptBin "td" (builtins.readFile ./td.sh))
      (writeShellScriptBin "tdl" (builtins.readFile ./tdl.sh))

      # Pi-coding-agent
      (writeShellScriptBin "pi" ''
        exec ${nodejs}/bin/npx -y @earendil-works/pi-coding-agent@latest "$@"
      '')

    ];

  programs.hunk = {
    enable = true;
    package = inputs.hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk;
    enableGitIntegration = false;
    settings = {
      theme = "catppuccin-mocha";
    };
  };

  # Configs from config folder
  xdg.configFile."opencode/opencode.json".source = ../../config/opencode/opencode.json;
  xdg.configFile."opencode/tui.json".source = ../../config/opencode/tui.json;

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
      push.autoSetupRemote = true;
      credential.helper = "!${pkgs.gh}/bin/gh auth git-credential";

      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
      };
    };
    lfs.enable = true;
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

  # Start syncthing (Linux only; on macOS use the Syncthing.app GUI)
  services.syncthing = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
  };

  # Home Manager needs to be able to update itself
  programs.home-manager.enable = true;
}
