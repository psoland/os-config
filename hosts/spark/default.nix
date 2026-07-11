{ ... }:

{
  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
    ../../modules/home/services/caddy.nix
    ../../modules/home/services/cloudflared.nix

    ./desktop.nix
    ./services/code-server.nix
    ./services/model-serving
  ];

  home.stateVersion = "25.11";
}
