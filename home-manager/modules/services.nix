{
  config,
  pkgs,
  lib,
  ...
}:

{
  # =========================================================================
  # code-server
  # VS Code in the browser, running as a systemd user service
  # =========================================================================

  # Install code-server
  home.packages = with pkgs; [
    code-server
  ];

  # code-server systemd user service
  systemd.user.services.code-server = {
    Unit = {
      Description = "VS Code Server";
      After = [ "network.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.code-server}/bin/code-server --bind-addr 127.0.0.1:8080 --auth none";
      Restart = "on-failure";
      RestartSec = 10;

      # Environment variables
      Environment = [
        "HOME=${config.home.homeDirectory}"
        "PATH=${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
      ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # code-server configuration
  home.file.".config/code-server/config.yaml".text = ''
    # code-server configuration
    # Binding to 127.0.0.1 - access via Tailscale IP forwarding
    bind-addr: 127.0.0.1:8080
    auth: none
    cert: false

    # Disable telemetry
    disable-telemetry: true
    disable-update-check: true
  '';

  # VS Code extensions to install with code-server
  # These will be installed on first run
  home.file.".config/code-server/install-extensions.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Install common VS Code extensions for code-server

      EXTENSIONS=(
        # Language support
        "golang.go"
        "ms-python.python"
        "esbenp.prettier-vscode"
        "dbaeumer.vscode-eslint"

        # Nix
        "jnoortheen.nix-ide"

        # Git
        "eamodio.gitlens"
        "mhutchie.git-graph"

        # Themes
        "catppuccin.catppuccin-vsc"

        # Utilities
        "usernamehw.errorlens"
        "streetsidesoftware.code-spell-checker"
        "EditorConfig.EditorConfig"
      )

      for ext in "''${EXTENSIONS[@]}"; do
        echo "Installing $ext..."
        code-server --install-extension "$ext" || true
      done

      echo "Extensions installed!"
    '';
  };

  # =========================================================================
  # DevPod Configuration
  # =========================================================================

  # DevPod is installed in dev-tools.nix
  # This sets up the Docker provider configuration

  home.file.".devpod/provider.yaml".text = ''
    # DevPod provider configuration
    # Using Docker as the primary provider
    name: docker
  '';

  # DevPod CLI configuration
  home.file.".config/devpod/config.yaml".text = ''
    # DevPod configuration
    current_context: default
    contexts:
      default:
        provider: docker
        options: {}
  '';

  # =========================================================================
  # Syncthing Configuration Notes
  # =========================================================================
  # Syncthing is installed via apt in the bootstrap script
  # and runs as a systemd user service.
  # 
  # The configure-syncthing.sh script will set it to only
  # listen on the Tailscale interface.
  #
  # Web UI: http://<tailscale-ip>:8384

  # =========================================================================
  # Tailscale SSH Configuration
  # =========================================================================
  # Tailscale SSH is configured in the bootstrap script.
  # Once authenticated, you can SSH via:
  #   ssh user@hostname  (using Tailscale hostname)
  #   ssh user@100.x.y.z (using Tailscale IP)
  #
  # UFW rules ensure SSH only works via the tailscale0 interface.
}
