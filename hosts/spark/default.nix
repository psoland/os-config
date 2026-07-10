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

  imports = [
    ../../modules/common.nix
    ../../modules/ghostty.nix
    ../../modules/caddy.nix
    ./model-serving.nix
  ];

  home.packages = with pkgs; [
    code-server
    ghostty
  ];

  systemd.user.services.code-server = {
    Unit = {
      Description = "code-server";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.code-server}/bin/code-server --bind-addr 127.0.0.1:8080 --auth none";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.cloudflared = {
    Unit = {
      Description = "Cloudflare Tunnel";
      After = [ "network.target" ];
    };

    Service = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %h/.config/cloudflared/token";
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home.stateVersion = "25.11";

}
