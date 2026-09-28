{
  pkgs,
  lib,
  config,
  ...
}:

{
  # The pinned native package currently supports Linux only. Keep V1 available
  # everywhere; its launchers and server config can migrate independently.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    (pkgs.callPackage ../../../packages/opencode2.nix { })
  ];

  # Keep entrypoints and helpers in one store tree so relative imports also
  # resolve correctly when the loader follows Home Manager's symlinks.
  xdg.configFile."opencode/plugins" = {
    source = ../../../config/opencode/plugins;
    recursive = true;
  };

  # V2 atomically replaces cli.json when saving preferences. Install a writable
  # copy, not a symlink that only appears immutable. The repository wins on every
  # activation; close V2 clients before activating to avoid concurrent writes.
  home.activation.opencodeCliConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p ${lib.escapeShellArg "${config.xdg.configHome}/opencode"}
    run install -m 600 ${../../../config/opencode/cli.json} ${lib.escapeShellArg "${config.xdg.configHome}/opencode/cli.json.hm-tmp"}
    run mv -f ${lib.escapeShellArg "${config.xdg.configHome}/opencode/cli.json.hm-tmp"} ${lib.escapeShellArg "${config.xdg.configHome}/opencode/cli.json"}
  '';

  programs.zsh.shellAliases = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    # The private server inherits the Bitwarden key; a previously running
    # shared server would not inherit variables from a newly launched client.
    oc2 = "varlock run -p \"$HOME/.dotfiles/config/opencode-knowit-ai-gateway-plugin\" --inject vars -- opencode2 --standalone";
    oc2-start = "varlock run -p \"$HOME/.dotfiles/config/opencode-knowit-ai-gateway-plugin\" --inject vars -- opencode2 service start";
    oc2-stop = "opencode2 service stop";
    oc2-reload = "varlock run -p \"$HOME/.dotfiles/config/opencode-knowit-ai-gateway-plugin\" --inject vars -- opencode2 service restart";
    oc2-status = "opencode2 service status";
  };
}
