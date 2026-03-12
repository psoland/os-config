{
  description = "Development shell template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Uncomment if you need unfree packages
          # config.allowUnfree = true;
        };
      in {
        devShells = {
          # Default development shell
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Add your project dependencies here

              # Example: Node.js project
              # nodejs_20
              # nodePackages.pnpm
              # nodePackages.typescript
              # nodePackages.typescript-language-server

              # Example: Python project
              # python312
              # python312Packages.pip
              # python312Packages.virtualenv
              # pyright

              # Example: Go project
              # go
              # gopls
              # golangci-lint
              # delve

              # Example: Rust project
              # rustc
              # cargo
              # rust-analyzer
              # rustfmt
              # clippy

              # Common tools
              just      # Command runner
              watchexec # File watcher
            ];

            # Environment variables
            # DATABASE_URL = "postgres://localhost/dev";

            shellHook = ''
              echo "Development shell activated!"
              echo ""
              echo "Available tools:"
              echo "  just --list   # Show available commands"
              echo ""

              # Example: Set up project-specific environment
              # export PROJECT_ROOT="$(pwd)"

              # Example: Create virtual environment for Python
              # if [ ! -d .venv ]; then
              #   python -m venv .venv
              # fi
              # source .venv/bin/activate

              # Example: Install Node dependencies
              # if [ ! -d node_modules ]; then
              #   pnpm install
              # fi
            '';
          };

          # Alternative shells for different scenarios

          # Node.js development shell
          node = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_20
              nodePackages.pnpm
              nodePackages.typescript
              nodePackages.typescript-language-server
              nodePackages.prettier
              nodePackages.eslint
            ];

            shellHook = ''
              echo "Node.js development shell"
              node --version
              pnpm --version
            '';
          };

          # Python development shell
          python = pkgs.mkShell {
            buildInputs = with pkgs; [
              python312
              python312Packages.pip
              python312Packages.virtualenv
              pyright
              ruff
              black
            ];

            shellHook = ''
              echo "Python development shell"
              python --version

              # Auto-create and activate virtualenv
              if [ ! -d .venv ]; then
                echo "Creating virtual environment..."
                python -m venv .venv
              fi
              source .venv/bin/activate
              echo "Virtual environment activated"
            '';
          };

          # Go development shell
          go = pkgs.mkShell {
            buildInputs = with pkgs; [
              go
              gopls
              golangci-lint
              delve
              gotools
              go-tools
            ];

            shellHook = ''
              echo "Go development shell"
              go version
              export GOPATH="$HOME/go"
              export PATH="$GOPATH/bin:$PATH"
            '';
          };

          # Full-stack development shell (example)
          fullstack = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Backend
              go
              gopls

              # Frontend
              nodejs_20
              nodePackages.pnpm

              # Database
              postgresql_16
              redis

              # Tools
              just
              watchexec
              process-compose
            ];

            shellHook = ''
              echo "Full-stack development shell"
              echo ""
              echo "Available services:"
              echo "  process-compose up  # Start all services"
              echo ""
            '';
          };
        };

        # Packages can also be defined if needed
        # packages.default = ...
      });
}
