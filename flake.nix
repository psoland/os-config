{
  description = "OS Configuration - Nix-based multi-platform setup";

  inputs = {
    # Nixpkgs - using unstable for latest packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager - follows nixpkgs to avoid duplicate downloads
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake utils for multi-system support
    flake-utils.url = "github:numtide/flake-utils";

    # OpenClaw Home Manager module and packages
    nix-openclaw.url = "github:openclaw/nix-openclaw";

    # Future: nix-darwin for macOS
    # darwin = {
    #   url = "github:lnl7/nix-darwin";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, home-manager, flake-utils, nix-openclaw, ... }:
    let
      # Supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        # Future macOS support:
        # "x86_64-darwin"
        # "aarch64-darwin"
      ];

      # Helper to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      });

      # Nixpkgs with OpenClaw overlay, used only by OpenClaw profiles
      nixpkgsForOpenclaw = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [ nix-openclaw.overlays.default ];
        config.allowUnfree = true;
      });

    in {
      # Home Manager configurations
      homeConfigurations = {
        # Oracle Ubuntu VM configuration for psoland user (x86_64)
        # Usage: home-manager switch --flake .#psoland-vm
        "psoland-vm" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsFor.x86_64-linux;
          modules = [
            ./hosts/oracle
            {
              home = {
                username = "psoland";
                homeDirectory = "/home/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self;
          };
        };

        # ARM64 Oracle Ubuntu VM for psoland user
        "psoland-vm-arm" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsFor.aarch64-linux;
          modules = [
            ./hosts/oracle
            {
              home = {
                username = "psoland";
                homeDirectory = "/home/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self;
          };
        };

        # Oracle Ubuntu VM with OpenClaw enabled (x86_64)
        "psoland-vm-openclaw" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsForOpenclaw.x86_64-linux;
          modules = [
            ./hosts/oracle/openclaw.nix
            {
              home = {
                username = "psoland";
                homeDirectory = "/home/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self;
            openclawModule = nix-openclaw.homeManagerModules.openclaw;
          };
        };

        # ARM64 Oracle Ubuntu VM with OpenClaw enabled
        "psoland-vm-arm-openclaw" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsForOpenclaw.aarch64-linux;
          modules = [
            ./hosts/oracle/openclaw.nix
            {
              home = {
                username = "psoland";
                homeDirectory = "/home/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self;
            openclawModule = nix-openclaw.homeManagerModules.openclaw;
          };
        };

        # Spark DGX Ubuntu configuration for psoland user (aarch64)
        "spark" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsFor.aarch64-linux;
          modules = [
            ./hosts/spark
            {
              home = {
                username = "psoland";
                homeDirectory = "/home/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self;
          };
        };

        # Future: macOS configuration
        # "macbook" = home-manager.lib.homeManagerConfiguration {
        #   pkgs = nixpkgsFor.aarch64-darwin;
        #   modules = [
        #     ./hosts/macbook
        #     {
        #       home = {
        #         username = "your-username";
        #         homeDirectory = "/Users/your-username";
        #       };
        #     }
        #   ];
        # };
      };

      # Templates for new projects
      templates = {
        devshell = {
          path = ./templates/devshell;
          description = "Development shell template with Node, Python, Go examples";
        };
      };

      # Development shells for this repository
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixpkgs-fmt
              nil
              statix
              repomix
            ];

            shellHook = ''
              echo "direnv: loading..."
            '';
          };
        }
      );

      # Formatter for nix files
      formatter = forAllSystems (system: nixpkgsFor.${system}.nixpkgs-fmt);
    };
}
