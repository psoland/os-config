{ pkgs, ... }:

# Only the route helper is managed by Home Manager. The proxy itself is a
# system service installed with hosts/spark/tailnet-proxy.sh.
let
  settings = builtins.fromJSON (builtins.readFile ../../../../config/tailnet/spark.json);

  tailnetctl = pkgs.writeShellApplication {
    name = "tailnetctl";
    runtimeInputs = [
      pkgs.caddy
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnused
      pkgs.iproute2
    ];
    runtimeEnv = {
      TAILNET_ZONE = settings.zone;
      TAILNET_ROUTES_DIR = settings.routesDir;
    };
    text = builtins.readFile ./tailnetctl.sh;
  };
in
{
  home.packages = [ tailnetctl ];
}
