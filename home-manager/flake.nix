{
  description = "OS configuration with Home Manager for Ubuntu and macOS";

  inputs = {
    # Nixpkgs - using unstable for latest packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixVim - Neovim configuration in Nix
    # Note: Not using follows per NixVim recommendation for stability
    nixvim.url = "github:nix-community/nixvim";

    # Future: nix-darwin for macOS
    # darwin = {
    #   url = "github:LnL7/nix-darwin";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixvim,
      ...
    }@inputs:
    let
      # Supported systems
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "aarch64-darwin" # 64-bit ARM macOS
        "x86_64-darwin" # 64-bit Intel macOS
      ];

      # Helper function for multi-system support
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
        );

      # Helper to create home-manager configurations
      mkHomeConfiguration =
        {
          system,
          username,
          homeDirectory ? (if builtins.match ".*-darwin" system != null then "/Users/${username}" else "/home/${username}"),
          modules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          extraSpecialArgs = {
            inherit inputs;
          };

          modules = [
            # Import NixVim as a Home Manager module
            nixvim.homeModules.nixvim

            # Base configuration
            ./home.nix

            # User-specific settings
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "24.05";
              };
            }
          ] ++ modules;
        };
    in
    {
      # Home Manager configurations
      homeConfigurations = {
        # Ubuntu VM configuration (default)
        "psoland@ubuntu" = mkHomeConfiguration {
          system = "x86_64-linux";
          username = "psoland";
        };

        # ARM Linux (e.g., Raspberry Pi, ARM VM)
        "psoland@ubuntu-arm" = mkHomeConfiguration {
          system = "aarch64-linux";
          username = "psoland";
        };

        # Future: macOS configuration
        # "psoland@macbook" = mkHomeConfiguration {
        #   system = "aarch64-darwin";
        #   username = "psoland";
        # };
      };

      # Development shell for working on this configuration
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              # Nix tools
              nixfmt-rfc-style
              nil # Nix LSP
              home-manager

              # Helpful utilities
              just
              git
            ];

            shellHook = ''
              echo "OS Config development shell"
              echo "Commands:"
              echo "  just switch  - Apply Home Manager configuration"
              echo "  just fmt     - Format Nix files"
              echo "  just check   - Check configuration without applying"
            '';
          };
        }
      );

      # Formatter (RFC 166 style)
      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
