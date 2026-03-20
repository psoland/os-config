{ ... }:

{
  # Zsh setup
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
      ll = "eza -la --icons";
      cx = "claude --dangerously-skip-permissions";

      # Nix
      init-dev = "nix flake init -t ~/.dotfiles#devshell";

      # Neovim in current folder
      v = "nvim .";

      # Opencode server in Tmux
      oc-start = "tmux has-session -t oc-serve 2>/dev/null || tmux new-session -d -s oc-serve 'opencode serve --hostname 0.0.0.0 --port 4090'";
      oc-log = "tmux attach-session -t oc-serve";
      oc-stop = "tmux kill-session -t oc-serve";
      oc-serve = "opencode --port 4091";

      zombiehunt = "ps -eo pid,ppid,stat,cmd,user | awk '\$3~\"Z\"' | awk '\$5~\"$USER\"'";

      # Tmux
      t = "tmux a || tmux new";
      tn = "tmux";
      tl = "tmux ls";

      # Git
      gco = "git checkout";
      gb = "git branch";
      gs = "git status";
      gpl = "git pull";
      gps = "git push";
      gpf = "git push --force";
      gbl = "git branch --list";
      gd = "git diff";
      ga = "git add .";
      gc = "git commit -m";
      gbd = "git branch -D";
      gca = "git commit --amend --no-edit";
      grc = "git rebase --continue";
      gra = "git rebase --abort";
      grr = "git restore . && git clean -fd";

    };

    # Injecting extra configs
    initContent = ''
      source ${./zsh_functions.sh}
      source ${./zsh_wt.sh}

      # Word navigation: opt+arrow (works locally and over SSH)
      # xterm-style sequences (\e[1;3C/D) and meta/emacs-style (\ef/\eb)
      bindkey '\e[1;3C' forward-word   # alt+right (xterm)
      bindkey '\e[1;3D' backward-word  # alt+left  (xterm)
      bindkey '\ef'     forward-word   # alt+right (meta/emacs)
      bindkey '\eb'     backward-word  # alt+left  (meta/emacs)

      # Word deletion: opt+backspace and opt+delete
      bindkey '\e^?'    backward-kill-word  # alt+backspace
      bindkey '\e[3;3~' kill-word           # alt+delete (xterm)
      bindkey '\ed'     kill-word           # alt+delete (meta/emacs)
    '';

  };

}
