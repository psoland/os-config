{ ... }:

{
  imports = [
    ./user.nix
    ../../modules/home/services/caddy.nix
    ../../modules/home/services/cloudflared.nix

    ./services/code-server.nix
    ./services/model-serving
  ];
}
