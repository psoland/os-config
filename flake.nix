{
  description = "OS Configuration - Nix + Home Manager for psoland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      mkHome = import ./lib/mkHome.nix { inherit inputs; };
    in {
      homeConfigurations = {
        "psoland@oracle-vm" = mkHome {
          hostname = "oracle-vm";
          username = "psoland";
          system = "x86_64-linux";
        };
      };

      # Dev shell for working on this config
      devShells.x86_64-linux.default = 
        let pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in pkgs.mkShell {
          buildInputs = with pkgs; [ nil nixpkgs-fmt just ];
        };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
