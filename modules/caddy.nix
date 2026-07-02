{ pkgs, ... }:

{
  home.packages = [ pkgs.caddy ];

  xdg.configFile."caddy/Caddyfile".source = ../config/caddy/Caddyfile;

  programs.zsh.shellAliases = {
    caddy-reload = "systemctl --user reload caddy";
  };

  systemd.user.services.caddy = {
    Unit = {
      Description = "Caddy reverse proxy";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.caddy}/bin/caddy run --config %h/.config/caddy/Caddyfile --adapter caddyfile";
      ExecReload = "${pkgs.caddy}/bin/caddy reload --config %h/.config/caddy/Caddyfile --adapter caddyfile";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
