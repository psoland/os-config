{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Custom package for lazysql
  lazysql = pkgs.stdenv.mkDerivation rec {
    pname = "lazysql";
    version = "0.3.2";

    src = pkgs.fetchurl {
      url = "https://github.com/jorgerojas26/lazysql/releases/download/v${version}/lazysql_Linux_x86_64.tar.gz";
      # You'll need to update this hash - run `nix-prefetch-url <url>` to get it
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    installPhase = ''
      mkdir -p $out/bin
      cp lazysql $out/bin/
      chmod +x $out/bin/lazysql
    '';

    meta = with lib; {
      description = "A cross-platform TUI database management tool";
      homepage = "https://github.com/jorgerojas26/lazysql";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

  # Custom package for opencode
  opencode = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "0.1.0"; # Update to actual version

    src = pkgs.fetchurl {
      url = "https://github.com/opencode-ai/opencode/releases/latest/download/opencode_Linux_x86_64.tar.gz";
      # You'll need to update this hash
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    installPhase = ''
      mkdir -p $out/bin
      cp opencode $out/bin/
      chmod +x $out/bin/opencode
    '';

    meta = with lib; {
      description = "AI-powered coding assistant";
      homepage = "https://github.com/opencode-ai/opencode";
      platforms = platforms.linux;
    };
  };
in
{
  # Development tools and language runtimes
  home.packages =
    with pkgs;
    [
      # =========================================================================
      # Language Runtimes
      # =========================================================================

      # Go
      go
      gopls
      go-tools # staticcheck, etc.
      golangci-lint
      delve # debugger

      # Node.js
      nodejs
      nodePackages.npm
      nodePackages.pnpm
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.prettier

      # Python
      python312
      python312Packages.pip
      python312Packages.virtualenv
      python312Packages.black
      python312Packages.isort
      python312Packages.pylint
      pyright

      # =========================================================================
      # Lazy* Tools
      # =========================================================================
      lazygit
      lazydocker

      # =========================================================================
      # Container & DevOps Tools
      # =========================================================================
      devpod
      kubectl
      kubernetes-helm
      k9s

      # =========================================================================
      # Database Tools
      # =========================================================================
      postgresql
      sqlite

      # =========================================================================
      # Other Dev Tools
      # =========================================================================
      gh # GitHub CLI
      pre-commit
      shellcheck
      shfmt
      httpie
      tokei # Code statistics
      hyperfine # Benchmarking
      watchexec # File watcher
    ]
    # Add custom packages only on Linux
    ++ lib.optionals pkgs.stdenv.isLinux [
      # Uncomment these after updating the sha256 hashes:
      # lazysql
      # opencode
    ];

  # Go environment configuration
  home.sessionVariables = {
    GOPATH = "${config.home.homeDirectory}/go";
    GOBIN = "${config.home.homeDirectory}/go/bin";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/go/bin"
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  # GitHub CLI configuration
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      aliases = {
        co = "pr checkout";
        pv = "pr view";
        pc = "pr create";
      };
    };
  };

  # Script to install lazysql manually (fallback)
  home.file.".local/bin/install-lazysql" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      VERSION="0.3.2"
      INSTALL_DIR="$HOME/.local/bin"
      mkdir -p "$INSTALL_DIR"

      echo "Installing lazysql v$VERSION..."

      ARCH=$(uname -m)
      case $ARCH in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
      esac

      OS=$(uname -s)

      curl -fsSL "https://github.com/jorgerojas26/lazysql/releases/download/v$VERSION/lazysql_''${OS}_$ARCH.tar.gz" | tar xz -C "$INSTALL_DIR"
      chmod +x "$INSTALL_DIR/lazysql"

      echo "lazysql installed to $INSTALL_DIR/lazysql"
    '';
  };

  # Script to install opencode manually (fallback)
  home.file.".local/bin/install-opencode" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      INSTALL_DIR="$HOME/.local/bin"
      mkdir -p "$INSTALL_DIR"

      echo "Installing opencode..."

      # Using the official install script
      curl -fsSL https://opencode.ai/install.sh | bash

      echo "opencode installed"
    '';
  };
}
