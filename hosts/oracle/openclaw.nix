{ inputs, ... }:

{
  imports = [
    ./default.nix
    inputs.nix-openclaw.homeManagerModules.openclaw
    ../../modules/openclaw.nix
  ];
}
