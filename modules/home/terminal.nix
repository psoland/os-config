# Terminal tools configuration (tmux, etc.)
{ config, pkgs, lib, ... }:

{
  programs.tmux = {
    enable = true;

    # Use 256 colors
    terminal = "tmux-256color";

    # Start windows and panes at 1, not 0
    baseIndex = 1;

    # Vi mode
    keyMode = "vi";

    # Mouse support
    mouse = true;

    # Longer history
    historyLimit = 50000;

    # Faster key repetition
    escapeTime = 0;

    # Enable focus events
    # focusEvents = true;

    # Prefix key (Ctrl+a instead of Ctrl+b)
    prefix = "C-a";

    # Sensible defaults
    sensibleOnTop = true;

    # Custom key bindings
    extraConfig = ''
      # True color support
      set -ag terminal-overrides ",xterm-256color:RGB"
      set -g default-terminal "tmux-256color"

      # Renumber windows when one is closed
      set -g renumber-windows on

      # Activity monitoring
      setw -g monitor-activity on
      set -g visual-activity off

      # Better split bindings
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # New window in current path
      bind c new-window -c "#{pane_current_path}"

      # Vim-like pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Vim-like pane resizing
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Quick pane cycling
      bind -r Tab select-pane -t :.+

      # Window navigation
      bind -r C-h previous-window
      bind -r C-l next-window

      # Reload config
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!"

      # Toggle synchronize-panes
      bind S set synchronize-panes \; display-message "Sync #{?synchronize-panes,ON,OFF}"

      # Copy mode improvements
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      # Quick session switching
      bind s choose-session

      # Kill pane/window shortcuts
      bind x kill-pane
      bind X kill-window

      # Status bar position
      set -g status-position top

      # Status bar styling (Catppuccin-inspired)
      set -g status-style "bg=#1e1e2e,fg=#cdd6f4"

      # Left side of status bar
      set -g status-left-length 50
      set -g status-left "#[bg=#89b4fa,fg=#1e1e2e,bold] #S #[bg=#1e1e2e,fg=#89b4fa]"

      # Right side of status bar
      set -g status-right-length 50
      set -g status-right "#[fg=#89b4fa]#[bg=#89b4fa,fg=#1e1e2e] %H:%M #[bg=#cba6f7,fg=#1e1e2e] %Y-%m-%d "

      # Window status
      set -g window-status-format " #I:#W "
      set -g window-status-current-format "#[bg=#cba6f7,fg=#1e1e2e,bold] #I:#W "
      set -g window-status-separator ""

      # Pane borders
      set -g pane-border-style "fg=#45475a"
      set -g pane-active-border-style "fg=#89b4fa"

      # Message styling
      set -g message-style "bg=#89b4fa,fg=#1e1e2e"
      set -g message-command-style "bg=#cba6f7,fg=#1e1e2e"

      # Clock mode
      set -g clock-mode-colour "#89b4fa"
      set -g clock-mode-style 24

      # Mode style (when in copy mode, etc.)
      set -g mode-style "bg=#45475a,fg=#cdd6f4"
    '';

    # Plugins managed by home-manager
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
      yank
      {
        plugin = vim-tmux-navigator;
        extraConfig = ''
          # Smart pane switching with awareness of Vim splits
        '';
      }
    ];
  };

  # Terminal multiplexer session manager
  home.packages = with pkgs; [
    # Terminal tools
    tmux
  ];
}
