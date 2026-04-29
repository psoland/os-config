{ pkgs, ... }:

{

  imports = [
    ../../modules/common.nix
  ];

  home.packages = with pkgs; [
    code-server
    llama-cpp
    python313Packages.huggingface-hub
  ];

  home.sessionVariables = {
    NVIM_ENABLE_MINUET = "1";
  };

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

  home.stateVersion = "25.11";

}
