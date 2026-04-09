{ ... }:

{

  imports = [
    ../../modules/common.nix
  ];

  services.code-server = {
    enable = true;
    bindAddr = "127.0.0.1:8080";
    auth = "none";
  };

  home.stateVersion = "25.11";

}
