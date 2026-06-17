{ ... }:
{
  xdg.configFile."ghostty/config".text = ''
    font-size=16
    theme = Catppuccin Mocha
    shell-integration-features = ssh-terminfo
    shell-integration-features = ssh-env
  '';
}
