{ ... }:

{

  programs.zsh.shellAliases = {
    ts-reauth = "/Applications/Tailscale.app/Contents/MacOS/Tailscale up --force-reauth";
  };

  imports = [
    ../../profiles/home/common.nix
    ../../modules/home/programs/ghostty.nix
    ../../modules/home/programs/rangr.nix
  ];

  home.stateVersion = "25.11";

}
