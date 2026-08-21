{ pkgs, inputs, ... }:

let
  ghostty = pkgs.runCommand "ghostty-with-host-gl" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.ghostty}/share "$out/share"

    cat > "$out/bin/ghostty" <<'EOF'
    #!${pkgs.runtimeShell}
    # NVIDIA's X11 EGL driver emits this non-fatal warning on every frame.
    exec ${
      inputs.nix-gl-host.packages.${pkgs.stdenv.hostPlatform.system}.default
    }/bin/nixglhost ${pkgs.ghostty}/bin/ghostty "$@" \
      2> >(${pkgs.gnugrep}/bin/grep --line-buffered -v 'eglExportDMABUFImage failed: 0x3009' >&2)
    EOF
    chmod +x "$out/bin/ghostty"
  '';

  installSparkDesktopApps = pkgs.writeShellApplication {
    name = "install-spark-desktop-apps";
    runtimeInputs = with pkgs; [
      coreutils
      curl
    ];
    text = ''
      if [ "$(uname -m)" != "aarch64" ] || [ ! -x /usr/bin/apt-get ]; then
        echo "This installer requires ARM64 Ubuntu or Debian." >&2
        exit 1
      fi

      download_dir="$(mktemp -d)"
      trap 'rm -rf "$download_dir"' EXIT

      curl --fail --location --retry 3 \
        --output "$download_dir/google-chrome-stable_current_arm64.deb" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb
      curl --fail --location --retry 3 \
        --output "$download_dir/chatgpt_arm64.deb" \
        https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb

      /usr/bin/sudo /usr/bin/apt-get update
      /usr/bin/sudo /usr/bin/apt-get install -y \
        "$download_dir/google-chrome-stable_current_arm64.deb" \
        "$download_dir/chatgpt_arm64.deb"
    '';
  };
in
{
  home.packages = [
    ghostty
    installSparkDesktopApps
  ];

  # GNOME watches this user directory, unlike the profile symlink, so its
  # launcher updates immediately and starts the host-graphics wrapper.
  xdg.dataFile."applications/com.mitchellh.ghostty.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Name=Ghostty
    Type=Application
    Comment=A terminal emulator
    Exec=${ghostty}/bin/ghostty
    Icon=${pkgs.ghostty}/share/icons/hicolor/512x512/apps/com.mitchellh.ghostty.png
    Categories=System;TerminalEmulator;
    Keywords=terminal;tty;pty;
    StartupNotify=true
    StartupWMClass=com.mitchellh.ghostty
    Terminal=false
    DBusActivatable=false
  '';
}
