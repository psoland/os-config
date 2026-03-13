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
    gcc
    fd
    jq
    lazygit
    #lazyvim
    lazysql
    devpod
    opencode
    syncthing
  ];

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
    userName = "Petter Søland";
    userEmail = "petter.soland@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.default = "current";
    };
  };

  # Zsh setp
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Natively configure history exactly like OMZ did
    history = {
      size = 10000;
      save = 10000;
      path = "$HOME/.zsh_history";
      ignoreDups = true;
      share = true;
    };

    shellAliases = {
      ll = "ls -la";

      # Git
      gco = "git checkout";
      gb  = "git branch";
      gs  = "git status";
      gpl = "git pull";
      gps = "git push";
      gpf = "git push --force";
      gbl = "git branch --list";
      gd  = "git diff";
      ga  = "git add .";
      gc  = "git commit -m";
      gbd = "git branch -D";
      gca = "git commit --amend --no-edit";
      grc = "git rebase --continue";
      gra = "git rebase --abort";
      grr = "git restore . && git clean -fd";
    };

    # Injecting extra configs
    initExtra = ''
      source ${./zsh_functions.sh}
      source ${./zsh_wt.sh}
    '';

    #oh-my-zsh = {
    #  enable = true;
    #  plugins =[ "git" "docker" "sudo" ];
    #  theme = "robbyrussell";
    #};
  };

  # Starship Prompt (Catppuccin Mocha Theme)
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      # Use the Catppuccin Mocha palette
      palette = "catppuccin_mocha";

      palettes.catppuccin_mocha = {
        rosewater = "#f5e0dc";
        flamingo  = "#f2cdcd";
        pink      = "#f5c2e7";
        mauve     = "#cba6f7";
        red       = "#f38ba8";
        maroon    = "#eba0ac";
        peach     = "#fab387";
        yellow    = "#f9e2af";
        green     = "#a6e3a1";
        teal      = "#94e2d5";
        sky       = "#89dceb";
        sapphire  = "#74c7ec";
        blue      = "#89b4fa";
        lavender  = "#b4befe";
        text      = "#cdd6f4";
        subtext1  = "#bac2de";
        subtext0  = "#a6adc8";
        overlay2  = "#9399b2";
        overlay1  = "#7f849c";
        overlay0  = "#6c7086";
        surface2  = "#585b70";
        surface1  = "#45475a";
        surface0  = "#313244";
        base      = "#1e1e2e";
        mantle    = "#181825";
        crust     = "#11111b";
      };

      # Optional: Make directory color pop with Catppuccin Lavender
      directory = {
        style = "bold lavender";
      };
      
      # Optional: Catppuccin colored prompt characters
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
    };
  };


  # Home Manager needs to be able to update itself
  programs.home-manager.enable = true;
}
