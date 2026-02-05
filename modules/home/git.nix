# Git configuration
{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;

    # User settings - override these in host config
    userName = lib.mkDefault "Your Name";
    userEmail = lib.mkDefault "your.email@example.com";

    # Core settings
    extraConfig = {
      init.defaultBranch = "main";

      core = {
        editor = "nvim";
        autocrlf = "input";
        whitespace = "fix";
        pager = "delta";
      };

      # Pull settings
      pull.rebase = true;

      # Push settings
      push = {
        default = "current";
        autoSetupRemote = true;
      };

      # Merge settings
      merge = {
        conflictstyle = "diff3";
        tool = "nvim";
      };

      # Diff settings
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
      };

      # Rebase settings
      rebase = {
        autoStash = true;
        autoSquash = true;
      };

      # Fetch settings
      fetch = {
        prune = true;
        pruneTags = true;
      };

      # Status settings
      status = {
        showUntrackedFiles = "all";
        submoduleSummary = true;
      };

      # Credential settings
      credential.helper = "cache --timeout=3600";

      # URL shortcuts
      url = {
        "git@github.com:" = {
          insteadOf = "gh:";
        };
        "git@gitlab.com:" = {
          insteadOf = "gl:";
        };
      };

      # Better logging
      log = {
        abbrevCommit = true;
        decorate = true;
      };

      # Column UI
      column.ui = "auto";

      # Rerere (reuse recorded resolution)
      rerere.enabled = true;

      # Help autocorrect
      help.autocorrect = 10;
    };

    # Aliases
    aliases = {
      # Status
      st = "status";
      s = "status -sb";

      # Commit
      ci = "commit";
      cm = "commit -m";
      ca = "commit --amend";
      can = "commit --amend --no-edit";

      # Checkout/Branch
      co = "checkout";
      cob = "checkout -b";
      br = "branch";
      bra = "branch -a";
      brd = "branch -d";

      # Diff
      d = "diff";
      ds = "diff --staged";
      dc = "diff --cached";

      # Log
      l = "log --oneline -20";
      lg = "log --oneline --graph --decorate";
      lga = "log --oneline --graph --decorate --all";
      ll = "log --pretty=format:'%C(yellow)%h%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

      # Push/Pull
      p = "push";
      pf = "push --force-with-lease";
      pl = "pull";
      f = "fetch --all --prune";

      # Stash
      ss = "stash save";
      sp = "stash pop";
      sl = "stash list";
      sd = "stash drop";

      # Reset
      unstage = "reset HEAD --";
      undo = "reset --soft HEAD^";
      hard = "reset --hard HEAD";

      # Cleanup
      cleanup = "!git branch --merged | grep -v '\\*\\|main\\|master' | xargs -n 1 git branch -d";

      # Quick add and commit
      ac = "!git add -A && git commit -m";

      # Show who contributed
      contrib = "shortlog -sn";

      # Find commits
      find = "!git log --pretty=format:'%C(yellow)%h %Cgreen%ad %Cblue%an%Creset: %s' --date=short --all --grep";

      # Show last commit
      last = "log -1 HEAD --stat";

      # List aliases
      aliases = "!git config --get-regexp '^alias\\.' | sed 's/alias\\.\\([^ ]*\\) \\(.*\\)/\\1\\\t=> \\2/' | sort";

      # Worktree shortcuts
      wt = "worktree";
      wta = "worktree add";
      wtl = "worktree list";
      wtr = "worktree remove";
    };

    # Global gitignore
    ignores = [
      # OS files
      ".DS_Store"
      "Thumbs.db"
      "Desktop.ini"

      # Editor files
      "*.swp"
      "*.swo"
      "*~"
      ".idea/"
      ".vscode/"
      "*.sublime-*"

      # Environment files
      ".env"
      ".env.local"
      ".envrc"

      # Nix
      "result"
      "result-*"

      # Python
      "__pycache__/"
      "*.py[cod]"
      ".Python"
      "venv/"
      ".venv/"

      # Node
      "node_modules/"
      "npm-debug.log"
      "yarn-error.log"

      # Build artifacts
      "*.o"
      "*.so"
      "*.a"
      "build/"
      "dist/"
      "target/"
    ];
  };

  # Delta for better diffs
  programs.git.delta = {
    enable = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = false;
      syntax-theme = "Dracula";

      file-style = "bold yellow ul";
      file-decoration-style = "none";

      hunk-header-style = "file line-number syntax";
      hunk-header-decoration-style = "blue box";

      line-numbers-left-style = "cyan";
      line-numbers-right-style = "cyan";
      line-numbers-minus-style = "red";
      line-numbers-plus-style = "green";

      minus-style = "syntax #3f0001";
      minus-emph-style = "syntax #901011";
      plus-style = "syntax #003800";
      plus-emph-style = "syntax #006000";
    };
  };

  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      aliases = {
        co = "pr checkout";
        pv = "pr view";
        pc = "pr create";
      };
    };
  };
}
