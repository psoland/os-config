{ pkgs, lib, ... }:

{
  systemd.user.services.opencode = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "OpenCode server";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4090";
      # Serve exposes the loopback-only server over authenticated Tailscale HTTPS.
      ExecStartPost = "-${pkgs.tailscale}/bin/tailscale serve --bg 4090";
      WorkingDirectory = "%h";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
