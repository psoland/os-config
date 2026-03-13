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

  };

}
