{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    
    shortcut = "s"; # Prefix to Ctrl+S
    mouse = true;
    baseIndex = 1;
    clock24 = true;

    extraConfig = ''
      # --- Standard settings ---
      set -g set-clipboard on
      set -g allow-passthrough on
      set-option -g status-position top
      set-option -g renumber-windows on

      # --- Keybinds ---
      unbind r
      bind r source-file ~/.tmux.conf

      # Vim navigation
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R

      # Rename window to folder name
      bind-key R rename-window "#{b:pane_current_path}"

      # Pane resizing med Ctrl+arrow
      bind-key -r -T prefix C-Left resize-pane -L
      bind-key -r -T prefix C-Right resize-pane -R
      bind-key -r -T prefix C-Up resize-pane -U
      bind-key -r -T prefix C-Down resize-pane -D

      # Pane resizing med Shift+arrow
      bind-key -r -T prefix S-Left resize-pane -L 5
      bind-key -r -T prefix S-Right resize-pane -R 5
      bind-key -r -T prefix S-Up resize-pane -U 5
      bind-key -r -T prefix S-Down resize-pane -D 5
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
        '';
      }
      {
        plugin = cpu;
        extraConfig = ''
          # Make the status line pretty
          set -g status-right-length 100
          set -g status-left-length 100
          set -g status-left ""

          set -g status-right "#{E:@catppuccin_status_directory}"
          set -agF status-right "#{E:@catppuccin_status_cpu}"
          set -ag status-right "#{E:@catppuccin_status_session}"
        '';
      }
    ];
  };

}
