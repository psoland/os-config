{ ... }:
{
  xdg.configFile."ghostty/config".text = ''
    font-size=16
    theme = Catppuccin Mocha
    shell-integration-features = ssh-terminfo
    shell-integration-features = ssh-env
    clipboard-paste-protection = false
    # Uncomment if Ctrl+Shift+H/L do not reach tmux as distinct keys over SSH.
    # keybind = ctrl+shift+h=csi:104;6u
    # keybind = ctrl+shift+l=csi:108;6u
  '';
}
