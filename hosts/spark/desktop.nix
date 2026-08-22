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
in
{
  home.packages = [ ghostty ];

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
