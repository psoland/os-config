{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [ ./tailscale-serve.nix ];

  programs.zsh.shellAliases = {
    oc-start = "systemctl --user start opencode";
    oc-log = "journalctl --user -fu opencode";
    oc-stop = "systemctl --user stop opencode";
    oc-reload = "systemctl --user restart opencode";
  };

  systemd.user.services.opencode = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "OpenCode server";
      After = [ "network.target" ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };

    Service = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4090";
      # Reconcile the shared route registry after the local server starts.
      ExecStartPost = "-${config.home.profileDirectory}/bin/tailscale-serve-reload";
      WorkingDirectory = "%h";
      Restart = "on-failure";
      RestartSec = 2;
      # Local MCP servers and other Home Manager packages are resolved by name.
      Environment = "PATH=${config.home.profileDirectory}/bin:/usr/local/bin:/usr/bin:/bin";
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
