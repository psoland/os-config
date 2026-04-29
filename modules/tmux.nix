{ pkgs, ... }:

let
  tmux-floax = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "floax";
    version = "unstable-2024-01-01";
    src = pkgs.fetchFromGitHub {
      owner = "omerxx";
      repo = "tmux-floax";
      rev = "133f526793d90d2caa323c47687dd5544a2c704b";
      hash = "sha256-9Hb9dn2qHF6KcIhtogvycX3Z0MoQrLPLCzZXtjGlPHw=";
    };
  };
in
{
  programs.tmux = {
    enable = true;

    shortcut = "s"; # Prefix to Ctrl+S
    mouse = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;

    extraConfig = ''
      # --- Standard settings ---
      set -g set-clipboard on
      set -g allow-passthrough on
      set-option -g status-position top
      set-option -g renumber-windows on
      setw -g aggressive-resize on
      setw -g mode-keys vi
      set -g status-interval 10
      # set -g repeat-time 1000

      # --- Colors ---
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",*:RGB"

      # --- Keybinds ---
      unbind r
      bind r source-file ~/.config/tmux/tmux.conf

      # Open new windows/splits in the current pane's working directory
      bind c new-window -c "#{pane_current_path}"
      bind '"' split-window -v -c "#{pane_current_path}"
      bind %   split-window -h -c "#{pane_current_path}"

      # Vim navigation
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R

      bind-key -r -T prefix C-h select-pane -L
      bind-key -r -T prefix C-j select-pane -D
      bind-key -r -T prefix C-k select-pane -U
      bind-key -r -T prefix C-l select-pane -R

      bind -r C-p previous-window
      bind -r C-n next-window

      # Vim-like copy mode
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi Enter send-keys -X copy-selection-and-cancel

      # Rename window to folder name
      bind-key R rename-window "#{b:pane_current_path}"

      # Pane resizing med Ctrl+arrow
      bind-key -r -T prefix C-Left resize-pane -L 5
      bind-key -r -T prefix C-Right resize-pane -R 5
      bind-key -r -T prefix C-Up resize-pane -U 5
      bind-key -r -T prefix C-Down resize-pane -D 5

      # Pane resizing med Shift+arrow
      bind-key -r -T prefix S-Left resize-pane -L
      bind-key -r -T prefix S-Right resize-pane -R
      bind-key -r -T prefix S-Up resize-pane -U
      bind-key -r -T prefix S-Down resize-pane -D
    '';

    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator
      {
        plugin = catppuccin;
        extraConfig = ''
          # --- Catppuccin Theme Config ---
          set -g @catppuccin_flavor "mocha"
          set -g @catppuccin_window_status_style "rounded"

          set -g @catppuccin_window_default_text "#W"
          set -g @catppuccin_window_text "#W"
          set -g @catppuccin_window_current_text "#W"

          # Show "<parent>/<current>" in the directory module so bare-repo
          # worktrees (foo/main, foo/feature-x) are distinguishable.
          set -g @catppuccin_directory_text "#{b:#{d:pane_current_path}}/#{b:pane_current_path}"
        '';
      }
      {
        plugin = cpu;
        extraConfig = ''
          # Make the status line pretty
          set -g status-right-length 100
          set -g status-left-length 100
          # Hostname on the left so it's obvious which machine you're on.
          set -g status-left "#{E:@catppuccin_status_host}"

          set -g status-right "#{E:@catppuccin_status_directory}"
          set -agF status-right "#{E:@catppuccin_status_cpu}"
          set -ag status-right "#{E:@catppuccin_status_session}"
        '';
      }
      {
        plugin = tmux-floax;
        extraConfig = ''
          set -g @floax-width '80%'
          set -g @floax-height '80%'
          set -g @floax-border-color 'magenta'
          set -g @floax-text-color 'blue'
          set -g @floax-change-path 'true'
        '';
      }
    ];
  };

}
