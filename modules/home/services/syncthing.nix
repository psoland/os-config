{ pkgs, ... }:

{
  home.packages = [ pkgs.syncthing ];
  services.syncthing.enable = true;
}
