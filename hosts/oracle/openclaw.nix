{ openclawModule, ... }:

{
  imports = [
    ./default.nix
    openclawModule
    ../../modules/openclaw.nix
  ];
}
