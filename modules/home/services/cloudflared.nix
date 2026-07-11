{ pkgs, ... }:

{
  systemd.user.services.cloudflared = {
    Unit = {
      Description = "Cloudflare Tunnel";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %h/.config/cloudflared/token";
      Restart = "always";
      RestartSec = 5;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
