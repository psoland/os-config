# Factory function for creating home-manager configurations
# Inspired by mitchellh's mksystem.nix and ironicbadger's helpers.nix
{ inputs }:

{
  hostname,
  username,
  system ? "x86_64-linux",
  stateVersion ? "24.05",
}:

let
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  
  modules = [
    ../hosts/${hostname}
    ../home/${username}.nix
    {
      home = {
        inherit username stateVersion;
        homeDirectory = "/home/${username}";
      };
    }
  ];
  
  extraSpecialArgs = {
    inherit inputs;
  };
}
