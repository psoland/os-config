{ ... }:

{
  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
    ./desktop.nix
  ];

  home.stateVersion = "25.11";
}
