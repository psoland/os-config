{ pkgs, lib, config, ... }:

{
  systemd.user.services.opencode = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "OpenCode server";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4090";
      # Reconcile the shared route registry after the local server starts.
      ExecStartPost = "-${config.dotfiles.tailscaleServe.reconcile}";
      WorkingDirectory = "%h";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install.WantedBy = [ "default.target" ];
  };

  dotfiles.tailscaleServe.routes = [
    {
      path = "/";
      target = "http://127.0.0.1:4090";
    }
    {
      path = "/opencode";
      target = "http://127.0.0.1:4090";
    }
  ];
}
