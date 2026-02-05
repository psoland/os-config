# ZSH configuration with plugins and modern prompt
{ config, pkgs, lib, ... }:

{
  # Zsh configuration
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    # History settings
    history = {
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      share = true;
    };

    # Shell options
    defaultKeymap = "emacs";

    # Initialize extra files
    initExtraFirst = ''
      # Powerlevel10k instant prompt (if using p10k)
      # if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
      #   source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      # fi
    '';

    initExtra = ''
      # Better directory navigation
      setopt AUTO_CD              # cd by typing directory name
      setopt AUTO_PUSHD           # Push directories to stack
      setopt PUSHD_IGNORE_DUPS    # Don't push duplicates
      setopt PUSHD_SILENT         # Don't print directory stack

      # Better completion
      setopt COMPLETE_IN_WORD     # Complete from cursor position
      setopt ALWAYS_TO_END        # Move cursor to end after completion
      setopt MENU_COMPLETE        # Show completion menu immediately

      # Better history
      setopt EXTENDED_HISTORY     # Record timestamp
      setopt HIST_VERIFY          # Don't execute immediately upon expansion
      setopt INC_APPEND_HISTORY   # Add commands as they are typed

      # Keybindings
      bindkey '^[[A' history-search-backward  # Up arrow
      bindkey '^[[B' history-search-forward   # Down arrow
      bindkey '^[[H' beginning-of-line        # Home
      bindkey '^[[F' end-of-line              # End
      bindkey '^[[3~' delete-char             # Delete
      bindkey '^[[1;5C' forward-word          # Ctrl+Right
      bindkey '^[[1;5D' backward-word         # Ctrl+Left

      # Better tab completion styling
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # Case insensitive
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' verbose yes
      zstyle ':completion:*:descriptions' format '%B%d%b'
      zstyle ':completion:*:messages' format '%d'
      zstyle ':completion:*:warnings' format 'No matches: %d'
      zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
      zstyle ':completion:*' group-name '''

      # Directory hashes for quick navigation
      hash -d code=~/code
      hash -d projects=~/projects
      hash -d config=~/os-config

      # Load local overrides if they exist
      [[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
    '';

    # Shell aliases
    shellAliases = {
      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "~" = "cd ~";

      # Modern replacements
      ls = "eza --icons";
      ll = "eza -la --icons --git";
      la = "eza -a --icons";
      lt = "eza --tree --icons --level=2";
      cat = "bat --style=plain";
      grep = "rg";
      find = "fd";

      # Git shortcuts
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      gd = "git diff";
      gco = "git checkout";
      gb = "git branch";
      glog = "git log --oneline --graph --decorate";

      # Docker shortcuts
      d = "docker";
      dc = "docker compose";
      dps = "docker ps";
      dlog = "docker logs";

      # Lazy tools
      lg = "lazygit";
      ld = "lazydocker";
      lsql = "lazysql";

      # System
      reload = "source ~/.zshrc";
      path = "echo $PATH | tr ':' '\n'";

      # Safety
      rm = "rm -i";
      cp = "cp -i";
      mv = "mv -i";

      # Misc
      vi = "nvim";
      vim = "nvim";
      c = "clear";
      h = "history";
      j = "jobs";

      # Home manager
      hms = "home-manager switch --flake ~/os-config#ubuntu-vm";
      hmu = "nix flake update ~/os-config && home-manager switch --flake ~/os-config#ubuntu-vm";
    };

    # Plugins managed by Nix
    plugins = [
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "v0.8.0";
          sha256 = "1lzrn0n4fxfcgg65v0qhnj7wnybybqzs4adz7xsrkgmcsr0ii8b7";
        };
      }
    ];
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
        "$nodejs"
        "$golang"
        "$rust"
        "$docker_context"
        "$line_break"
        "$character"
      ];

      # Prompt character
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
        vimcmd_symbol = "[❮](bold green)";
      };

      # Directory
      directory = {
        truncation_length = 4;
        truncate_to_repo = true;
        style = "bold cyan";
      };

      # Git
      git_branch = {
        symbol = " ";
        style = "bold purple";
      };

      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
        style = "bold red";
        conflicted = "=";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        untracked = "?\${count}";
        stashed = "\\$";
        modified = "!\${count}";
        staged = "+\${count}";
        renamed = "»\${count}";
        deleted = "✘\${count}";
      };

      # Nix shell indicator
      nix_shell = {
        symbol = " ";
        format = "[$symbol$state( \\($name\\))]($style) ";
        style = "bold blue";
      };

      # Language versions (shown when in project)
      python = {
        symbol = " ";
        style = "yellow";
      };

      nodejs = {
        symbol = " ";
        style = "green";
      };

      golang = {
        symbol = " ";
        style = "cyan";
      };

      rust = {
        symbol = " ";
        style = "red";
      };

      # Docker context
      docker_context = {
        symbol = " ";
        style = "blue";
        only_with_files = true;
      };

      # Don't show username/hostname in most cases
      username = {
        show_always = false;
        format = "[$user]($style)@";
      };

      hostname = {
        ssh_only = true;
        format = "[$hostname]($style) ";
        style = "bold green";
      };
    };
  };

  # FZF integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
    ];

    # Ctrl+T to search files
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [
      "--preview 'bat --style=numbers --color=always {}'"
    ];

    # Alt+C to cd to directory
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    changeDirWidgetOptions = [
      "--preview 'eza --tree --level=2 --icons {}'"
    ];

    # Ctrl+R for history (enabled by default)
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
  };

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;

    # Whitelist directories (optional, for security)
    # config = {
    #   whitelist = {
    #     prefix = [ "~/code" "~/projects" ];
    #   };
    # };
  };

  # Zoxide for smart cd
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ];  # Replace cd with zoxide
  };
}
