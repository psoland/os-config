{
  description = "OS Configuration - Nix-based multi-platform setup";

  inputs = {
    # Nixpkgs - using unstable for latest packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # TODO: Remove once https://github.com/cachix/devenv/issues/2842 is fixed in nixpkgs.
    # Pin devenv to 2.1.0 until the GitHub HTTPS-to-SSH lock regression is fixed.
    nixpkgs-devenv-210.url = "github:NixOS/nixpkgs/f962f9d446110b36d617402641005542df1a011a";

    # Home Manager - follows nixpkgs to avoid duplicate downloads
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake utils for multi-system support
    flake-utils.url = "github:numtide/flake-utils";

    # Hunk diff viewer
    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-darwin for macOS
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      flake-utils,
      darwin,
      ...
    }:
    let
      # Supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Helper to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for each system
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );

    in
    {
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
            inherit self inputs;
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
            inherit self inputs;
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
            inherit self inputs;
          };
        };

        # Personal MacBook (Apple Silicon) — standalone Home Manager
        # Usage: home-manager switch --flake .#psoland-mac
        "psoland-mac" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsFor.aarch64-darwin;
          modules = [
            ./hosts/mac/personal.nix
            {
              home = {
                username = "psoland";
                homeDirectory = "/Users/psoland";
              };
            }
          ];
          extraSpecialArgs = {
            inherit self inputs;
          };
        };
      };

      # nix-darwin configurations for macOS hosts
      darwinConfigurations = {
        # Future: uncomment when personal Mac moves to nix-darwin
        # "psoland-mac" = darwin.lib.darwinSystem {
        #   system = "aarch64-darwin";
        #   modules = [
        #     home-manager.darwinModules.home-manager
        #     {
        #       users.users.psoland = {
        #         name = "psoland";
        #         home = "/Users/psoland";
        #       };
        #       nixpkgs.config.allowUnfree = true;
        #       home-manager = {
        #         useGlobalPkgs = true;
        #         useUserPackages = true;
        #         extraSpecialArgs = {
        #           inherit self;
        #         };
        #         users.psoland = ./hosts/mac/personal.nix;
        #       };
        #     }
        #   ];
        # };

        # Work MacBook (Apple Silicon) — nix-darwin + Home Manager + brew/dock
        # Usage: darwin-rebuild switch --flake .#pettersoland-mac
        "pettersoland-mac" = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            home-manager.darwinModules.home-manager
            ./modules/darwin/darwin.nix
            {
              system.primaryUser = "pettersoland";

              users.users.pettersoland = {
                name = "pettersoland";
                home = "/Users/pettersoland";
              };
              nixpkgs.config.allowUnfree = true;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit self inputs;
                };
                users.pettersoland = ./hosts/mac/work.nix;
              };
            }
          ];
        };
      };

      # Templates for new projects
      templates = {
        devshell = {
          path = ./templates/devshell;
          description = "Development shell template with Node, Python, Go examples";
        };
        python = {
          path = ./templates/python;
          description = "Python + uv development shell template";
        };
        typescript = {
          path = ./templates/typescript;
          description = "TypeScript development shell template";
        };
        devenv = {
          path = ./templates/devenv;
          description = "Devenv template with Node and Python examples";
        };
        devenv-python = {
          path = ./templates/devenv-python;
          description = "Python + uv devenv template";
        };
        devenv-typescript = {
          path = ./templates/devenv-typescript;
          description = "TypeScript devenv template";
        };
        devenv-terraform = {
          path = ./templates/devenv-terraform;
          description = "Terraform devenv template";
        };
      };

      # Development shells for this repository
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixfmt
              nixfmt-tree
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

      # Formatter for Nix files. nixfmt-tree wraps nixfmt so `nix fmt .`
      # handles directories.
      formatter = forAllSystems (system: nixpkgsFor.${system}.nixfmt-tree);
    };
}
