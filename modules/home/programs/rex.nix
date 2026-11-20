{
  config,
  inputs,
  pkgs,
  ...
}:
# Rex server for a Linux host reached from other machines over SSH:
#   rex hosts add spark ssh://psoland@spark
let
  rex = inputs.rex.packages.${pkgs.stdenv.hostPlatform.system}.rex;
in
{
  imports = [ inputs.rex.homeModules.default ];

  programs.rex = {
    enable = true;
    package = rex;
    # The guard needs programs.ssh.enable, which this repo leaves off; outgoing
    # ssh from a Rex terminal would send TERM=xterm-rex. Run `rex terminfo setup`
    # if that becomes a problem on a target host.
    sshGuard = false;
  };

  # Long-running personal server (systemd user unit `rex`); lingering keeps it
  # alive while logged out. home-manager switch never restarts it, so run
  # `systemctl --user restart rex` after an update (this ends every session).
  services.rex.enable = true;

  # `ssh host rex ...` runs a non-login shell without the Nix profile on PATH;
  # Rex also looks in ~/.local/bin.
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
  home.file.".local/bin/rex".source = "${rex}/bin/rex";
}
