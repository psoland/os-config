{
  description = "Cross-platform Nix configuration for macOS and Linux";

  inputs = {
    # Nixpkgs stable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # Nixpkgs unstable - for packages that need latest versions
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Home Manager - for user environment management
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # nix-darwin - for macOS system management
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nix-darwin, ... }:
    let
      # Helper function to create home-manager configurations
      mkHomeConfiguration = { system, modules }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { 
            inherit system;
            config.allowUnfree = true;
          };
          
          extraSpecialArgs = {
            # Make unstable packages available to all modules
            pkgs-unstable = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          
          modules = modules;
        };
    in
    {
      # Home Manager configurations for Linux systems
      homeConfigurations = {
        # Ubuntu configuration
        ubuntu = mkHomeConfiguration {
          system = "x86_64-linux";
          modules = [ ./hosts/ubuntu/default.nix ];
        };
        
        # Spark OS configuration
        spark = mkHomeConfiguration {
          system = "x86_64-linux";
          modules = [ ./hosts/spark/default.nix ];
        };
        
        # Docker testing configuration
        psoland = mkHomeConfiguration {
          system = "x86_64-linux";
          modules = [ ./hosts/ubuntu/default.nix ];
        };
      };
      
      # nix-darwin configuration for macOS
      darwinConfigurations = {
        psoland = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";  # Change to x86_64-darwin for Intel Macs
          
          modules = [
            ./hosts/macbook/darwin.nix
            
            # Integrate home-manager with nix-darwin
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                
                # Make unstable packages available
                extraSpecialArgs = {
                  pkgs-unstable = import nixpkgs-unstable {
                    system = "aarch64-darwin";  # Change to x86_64-darwin for Intel
                    config.allowUnfree = true;
                  };
                };
                
                users.psoland = import ./hosts/macbook/home.nix;
              };
            }
          ];
        };
      };
      
      # Development shells for testing (optional)
      devShells = {
        # Linux development shell
        x86_64-linux.default = let
          pkgs = import nixpkgs { 
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        in pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            neovim
          ];
          
          shellHook = ''
            echo "Nix development environment loaded"
            echo "Use 'nix flake check' to validate the configuration"
          '';
        };
        
        # macOS development shell
        aarch64-darwin.default = let
          pkgs = import nixpkgs { 
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        in pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            neovim
          ];
          
          shellHook = ''
            echo "Nix development environment loaded"
            echo "Use 'nix flake check' to validate the configuration"
          '';
        };
      };
    };
}
