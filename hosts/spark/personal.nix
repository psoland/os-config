{ ... }:

{
  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
    ./desktop.nix
    ./desktop-apps.nix
    ../../modules/home/services/syncthing.nix
    ../../modules/home/services/opencode.nix
    ../../modules/home/services/caddy.nix
    ../../modules/home/services/cloudflared.nix
    ../../modules/home/services/nix-disk-cleanup.nix
    ./services/model-serving
  ];

  home.stateVersion = "25.11";
}
