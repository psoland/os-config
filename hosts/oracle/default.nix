{ ... }:

{

  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/services/syncthing.nix
    ../../modules/home/services/opencode.nix
    ../../modules/home/services/nix-disk-cleanup.nix
  ];

  home.stateVersion = "25.11";

}
