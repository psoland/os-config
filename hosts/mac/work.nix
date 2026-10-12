{ pkgs, ... }:

{

  home.packages = [
    (pkgs.writeShellApplication {
      name = "mindmeld-install";
      runtimeInputs = with pkgs; [
        gh
        coreutils
        bash
      ];
      text = builtins.readFile ./install-mindmeld.sh;
    })
  ];

  programs.zsh.shellAliases = {
    ts-reauth = "/Applications/Tailscale.app/Contents/MacOS/Tailscale up --force-reauth";
  };

  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
  ];

  home.stateVersion = "25.11";

}
