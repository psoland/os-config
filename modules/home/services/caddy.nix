{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.dotfiles.caddy;
in
{
  options.dotfiles.caddy = {
    adminAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:2020";
      description = "Private admin listener, separate from the aiservices proxy on port 2019.";
    };
    configText = lib.mkOption {
      type = lib.types.lines;
      default = ''
        http://:18000 {
          bind 127.0.0.1
          respond "caddy is running" 200
        }
      '';
      description = "Caddyfile contents.";
    };
  };

  config = {
    home.packages = [ pkgs.caddy ];

    xdg.configFile."caddy/Caddyfile".text = ''
      {
        admin ${cfg.adminAddress}
      }
    ''
    + cfg.configText;

    programs.zsh.shellAliases = {
      caddy-reload = "systemctl --user reload caddy";
    };

    home.activation.reloadCaddy =
      lib.hm.dag.entryAfter
        [
          "linkGeneration"
          "initializeVllmRegistry"
        ]
        ''
          if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet caddy; then
            $DRY_RUN_CMD systemctl --user reload caddy || true
          fi
        '';

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
  };
}
