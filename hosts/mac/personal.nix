{ ... }:

{

  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
  ];

  home.stateVersion = "25.11";

}
