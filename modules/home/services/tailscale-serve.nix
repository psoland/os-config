{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.dotfiles.tailscaleServe;
  normalizedPaths = map (route: lib.removeSuffix "/" route.path) cfg.routes;

  reconcile = pkgs.writeShellScriptBin "tailscale-serve-reload" ''
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
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (route: lib.hasPrefix "/" route.path) cfg.routes;
        message = "Tailscale Serve route paths must start with '/'.";
      }
      {
        assertion = lib.length (lib.unique normalizedPaths) == lib.length cfg.routes;
        message = "Tailscale Serve route paths must be unique, ignoring a trailing '/'.";
      }
    ];

    home.packages = [ reconcile ];
  };
}
