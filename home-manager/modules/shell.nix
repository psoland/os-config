{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Zsh configuration with Oh-My-Zsh
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    # History settings
    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
      share = true;
    };

    # Oh-My-Zsh
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "docker"
        "docker-compose"
        "kubectl"
        "golang"
        "npm"
        "python"
        "pip"
        "sudo"
        "history"
        "command-not-found"
        "colored-man-pages"
        "extract"
        "z"
      ];
      # Theme is handled by starship
      theme = "";
    };

    # Shell aliases
    shellAliases = {
      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";

      # Modern replacements
      ls = "eza --icons --group-directories-first";
      ll = "eza -la --icons --group-directories-first";
      la = "eza -a --icons --group-directories-first";
      lt = "eza --tree --level=2 --icons";
      cat = "bat";

      # Git shortcuts (in addition to oh-my-zsh git plugin)
      g = "git";
      gs = "git status";
      gd = "git diff";
      gp = "git push";
      gl = "git pull";
      gco = "git checkout";
      gcm = "git commit -m";
      gca = "git commit --amend";
      gb = "git branch";
      glog = "git log --oneline --graph --decorate -20";

      # Lazy tools
      lg = "lazygit";
      ld = "lazydocker";
      lsql = "lazysql";

      # Docker
      d = "docker";
      dc = "docker compose";
      dps = "docker ps";
      dpa = "docker ps -a";
      di = "docker images";

      # Nix / Home Manager
      hms = "home-manager switch --flake ~/os-config/home-manager";
      hmu = "nix flake update ~/os-config/home-manager && home-manager switch --flake ~/os-config/home-manager";

      # Misc
      vim = "nvim";
      vi = "nvim";
      v = "nvim";
      c = "clear";
      reload = "source ~/.zshrc";
      path = "echo $PATH | tr ':' '\\n'";

      # Quick edit configs
      zshrc = "nvim ~/.zshrc";
      nixconf = "nvim ~/os-config/home-manager";
    };

    # Initialize tools
    initExtra = ''
      # Initialize zoxide (smart cd)
      eval "$(zoxide init zsh)"

      # Initialize fzf
      if [ -f ~/.fzf.zsh ]; then
        source ~/.fzf.zsh
      fi

      # FZF configuration
      export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
      export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
      export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

      # Better history search with fzf
      bindkey '^R' fzf-history-widget

      # Quick directory navigation with zoxide
      alias cd='z'

      # Load any local customizations
      if [ -f ~/.zshrc.local ]; then
        source ~/.zshrc.local
      fi
    '';

    # Environment variables for login shells
    profileExtra = ''
      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
    '';
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      # Prompt format
      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$nix_shell"
        "$python"
        "$golang"
        "$nodejs"
        "$docker_context"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];

      # Modules configuration
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };

      directory = {
        truncation_length = 4;
        truncate_to_repo = true;
        style = "bold cyan";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
      };

      git_status = {
        style = "bold red";
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
      };

      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state]($style) ";
        style = "bold blue";
      };

      python = {
        symbol = " ";
        format = "via [$symbol$version]($style) ";
      };

      golang = {
        symbol = " ";
        format = "via [$symbol$version]($style) ";
      };

      nodejs = {
        symbol = " ";
        format = "via [$symbol$version]($style) ";
      };

      docker_context = {
        symbol = " ";
        format = "via [$symbol$context]($style) ";
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
        style = "bold yellow";
      };

      hostname = {
        ssh_only = true;
        format = "[@$hostname]($style) ";
        style = "bold green";
      };

      username = {
        show_always = false;
        format = "[$user]($style)";
        style_user = "bold blue";
      };
    };
  };

  # FZF configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
  };

  # Zoxide (smart cd)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
