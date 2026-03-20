{ ... }:

{
  programs.openclaw = {
    enable = true;
    documents = ../openclaw-documents;

    config = {
      gateway = {
        mode = "local";
        auth = {
          token = "CHANGE_ME_OPENCLAW_GATEWAY_TOKEN";
        };
      };

      channels.telegram = {
        tokenFile = "/home/psoland/.secrets/openclaw-telegram-token";
        allowFrom = [ 0 ];
        groups = {
          "*" = {
            requireMention = true;
          };
        };
      };
    };

    instances.default.enable = true;
  };
}
