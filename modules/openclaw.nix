{ ... }:

{
  programs.openclaw = {
    enable = true;
    documents = ../openclaw-documents;

    instances.default = {
      enable = true;
      logPath = "/home/psoland/.openclaw/logs/openclaw-gateway.log";

      config = {
        secrets.providers.local = {
          source = "env";
          allowlist = [
            "OPENCLAW_GATEWAY_TOKEN"
          ];
        };

        gateway = {
          mode = "local";
          auth = {
            token = {
              source = "env";
              provider = "local";
              id = "OPENCLAW_GATEWAY_TOKEN";
            };
          };
        };

        channels.whatsapp = {
          enabled = true;
          defaultAccount = "default";
          accounts.default = {
            enabled = true;
            authDir = "/home/psoland/.openclaw/whatsapp";
            dmPolicy = "pairing";
            groupPolicy = "open";
            groups = {
              "*" = {
                requireMention = true;
              };
            };
          };
        };

        # models.providers.github-copilot = {
        #   api = "github-copilot";
        #   auth = "token";
        #   baseUrl = "https://api.individual.githubcopilot.com";
        #   apiKey = {
        #     source = "env";
        #     provider = "local";
        #     id = "COPILOT_GITHUB_TOKEN";
        #   };
        #   models = [ ];
        # };
      };
    };
  };

  systemd.user.services.openclaw-gateway.Service.EnvironmentFile = [
    "/home/psoland/.secrets/openclaw.env"
  ];
}
