{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.dotfiles.tailscaleServe;

  reconcile = pkgs.writeShellScript "tailscale-serve-reconcile" ''
    set -euo pipefail

    ${pkgs.tailscale}/bin/tailscale serve reset
    ${lib.concatMapStringsSep "\n" (
      route:
      "${pkgs.tailscale}/bin/tailscale serve --bg --set-path=${lib.escapeShellArg route.path} ${lib.escapeShellArg route.target}"
    ) cfg.routes}
  '';
in
{
  options.dotfiles.tailscaleServe = {
    routes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "URL path exposed through Tailscale Serve.";
            };
            target = lib.mkOption {
              type = lib.types.str;
              description = "Local HTTP target for the route.";
            };
          };
        }
      );
      default = [ ];
      description = "Node-level Tailscale Serve routes managed by this configuration.";
    };

    reconcile = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      description = "Script that reconciles Tailscale Serve with routes.";
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (route: lib.hasPrefix "/" route.path) cfg.routes;
        message = "Tailscale Serve route paths must start with '/'.";
      }
      {
        assertion = lib.length (lib.unique (map (route: route.path) cfg.routes)) == lib.length cfg.routes;
        message = "Tailscale Serve route paths must be unique.";
      }
    ];

    dotfiles.tailscaleServe.reconcile = reconcile;
  };
}
