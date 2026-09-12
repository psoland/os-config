{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  systemd.user.services.tailscale-taildrop = {
    Unit = {
      Description = "Receive files via Tailscale Taildrop";
      After = [ "network.target" ];
    };

    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${config.home.homeDirectory}/Downloads";
      ExecStart = "${pkgs.tailscale}/bin/tailscale file get --loop --conflict=rename ${config.home.homeDirectory}/Downloads";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
