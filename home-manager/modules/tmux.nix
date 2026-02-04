{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "tmux-256color";

    # Use C-a as prefix (like screen)
    prefix = "C-a";

    # Start windows and panes at 1, not 0
    baseIndex = 1;

    # Enable mouse support
    mouse = true;

    # History limit
    historyLimit = 50000;

    # Faster escape time for nvim
    escapeTime = 10;

    # Enable focus events
    focusEvents = true;

    # Clock mode
    clock24 = true;

    # Key mode
    keyMode = "vi";

    # Plugins
    plugins = with pkgs.tmuxPlugins; [
      # Sensible defaults
      sensible

      # Vim-like navigation
      vim-tmux-navigator

      # Better copy mode
      yank

      # Session management
      resurrect
      continuum

      # Status bar theme
      catppuccin

      # CPU/Memory display
      cpu

      # Better pane management
      pain-control

      # Quick session switching
      sessionist
    ];

    extraConfig = ''
      # True color support
      set -ag terminal-overrides ",xterm-256color:RGB"

      # Split panes using | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Create new window in current path
      bind c new-window -c "#{pane_current_path}"

      # Reload config
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # Switch panes using Alt-arrow without prefix
      bind -n M-Left select-pane -L
      bind -n M-Right select-pane -R
      bind -n M-Up select-pane -U
      bind -n M-Down select-pane -D

      # Vim-like pane switching
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Resize panes with vim keys
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Quick window switching
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9

      # Don't rename windows automatically
      set-option -g allow-rename off

      # Activity monitoring
      setw -g monitor-activity on
      set -g visual-activity off

      # Catppuccin theme configuration
      set -g @catppuccin_window_left_separator ""
      set -g @catppuccin_window_right_separator " "
      set -g @catppuccin_window_middle_separator " █"
      set -g @catppuccin_window_number_position "right"

      set -g @catppuccin_window_default_fill "number"
      set -g @catppuccin_window_default_text "#W"

      set -g @catppuccin_window_current_fill "number"
      set -g @catppuccin_window_current_text "#W"

      set -g @catppuccin_status_modules_right "directory session host cpu"
      set -g @catppuccin_status_left_separator  " "
      set -g @catppuccin_status_right_separator ""
      set -g @catppuccin_status_fill "icon"
      set -g @catppuccin_status_connect_separator "no"

      set -g @catppuccin_directory_text "#{pane_current_path}"

      # Resurrect configuration
      set -g @resurrect-capture-pane-contents 'on'
      set -g @resurrect-strategy-nvim 'session'

      # Continuum configuration
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '15'

      # Copy mode improvements
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -i"
      bind-key -T copy-mode-vi r send-keys -X rectangle-toggle

      # Quick session switching
      bind S choose-session
      bind N command-prompt -p "New session name:" "new-session -s '%%'"

      # Kill pane/window shortcuts
      bind x kill-pane
      bind X kill-window
      bind Q confirm-before -p "Kill session #S? (y/n)" kill-session
    '';
  };
}
