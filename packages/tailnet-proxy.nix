{
  lib,
  stdenvNoCC,
  writeText,
  writeShellScript,
  coreutils,
  cacert,
  caddy-cloudflare,
}:

# System Caddy that serves https://<name>.<zone> for each configured zone, on the
# Tailscale address only.
# Routes live in mutable snippets under `routesDir`, managed by `tailnetctl`.
let
  settings = builtins.fromJSON (builtins.readFile ../config/tailnet/spark.json);
  inherit (settings) zones tailscaleIPv4 routesDir;
  validZone =
    zone:
    builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+" zone != null;

  ipNumbers = map lib.toInt (lib.splitString "." tailscaleIPv4);
  validIP =
    builtins.match "100\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" tailscaleIPv4 != null
    && lib.all (n: n <= 255) ipNumbers
    && builtins.elemAt ipNumbers 1 >= 64
    && builtins.elemAt ipNumbers 1 <= 127;

  config = writeText "mujo-tailnet-Caddyfile" ''
    {
    	admin unix//run/mujo-tailnet-caddy/admin.sock
    	default_bind ${tailscaleIPv4}
    	auto_https disable_redirects
    	servers {
    		protocols h1 h2
    	}
    	acme_dns cloudflare {env.CF_API_TOKEN}
    }

    ${lib.concatMapStringsSep ", " (zone: "*.${zone}") zones} {
    	import ${routesDir}/*.caddy

    	handle {
    		respond "No tailnet service is configured for {host}" 404
    	}
    }
  '';

  runner = writeShellScript "mujo-tailnet-caddy" ''
    set -eu
    # Read only at runtime. Never use --environ or shell tracing here.
    CF_API_TOKEN="$(${coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/cloudflare-token")"
    test -n "$CF_API_TOKEN" || { echo "Missing Cloudflare credential" >&2; exit 1; }
    export CF_API_TOKEN
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    case "$1" in
      run|reload) exec ${caddy-cloudflare}/bin/caddy "$1" --config ${config} --adapter caddyfile ;;
      *) exit 2 ;;
    esac
  '';

  unit = writeText "mujo-tailnet-caddy.service" ''
    # Managed by dotfiles/packages/tailnet-proxy.nix
    [Unit]
    Description=Private tailnet HTTPS proxy (${lib.concatStringsSep ", " zones})
    Wants=network-online.target tailscaled.service
    After=network-online.target tailscaled.service
    StartLimitIntervalSec=0

    [Service]
    Type=simple
    DynamicUser=true
    User=mujo-tailnet-caddy
    StateDirectory=mujo-tailnet-caddy
    StateDirectoryMode=0700
    RuntimeDirectory=mujo-tailnet-caddy
    RuntimeDirectoryMode=0700
    Environment=HOME=/var/lib/mujo-tailnet-caddy
    Environment=XDG_DATA_HOME=/var/lib/mujo-tailnet-caddy/data
    Environment=XDG_CONFIG_HOME=/var/lib/mujo-tailnet-caddy/config
    LoadCredential=cloudflare-token:/etc/mujo-tailnet/cloudflare-token
    ExecStart=${runner} run
    ExecReload=${runner} reload
    # The Tailscale address may not exist yet at boot; retry until it does.
    Restart=on-failure
    RestartSec=10
    TimeoutStopSec=30
    AmbientCapabilities=CAP_NET_BIND_SERVICE
    CapabilityBoundingSet=CAP_NET_BIND_SERVICE
    NoNewPrivileges=true
    PrivateTmp=true
    PrivateDevices=true
    ProtectSystem=strict
    ProtectHome=true
    ProtectKernelTunables=true
    ProtectKernelModules=true
    ProtectControlGroups=true
    RestrictSUIDSGID=true
    RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
    UMask=0077

    [Install]
    WantedBy=multi-user.target
  '';
in
assert lib.assertMsg stdenvNoCC.hostPlatform.isLinux "The tailnet proxy requires Linux/systemd.";
assert lib.assertMsg validIP "tailscaleIPv4 must be in Tailscale's 100.64.0.0/10 range.";
assert lib.assertMsg (
  zones != [ ] && lib.all validZone zones && lib.unique zones == zones
) "zones must be a non-empty list of distinct lowercase domains.";
assert lib.assertMsg (
  builtins.match "/[A-Za-z0-9/_.-]+" routesDir != null
) "routesDir must be an absolute path.";
stdenvNoCC.mkDerivation {
  name = "mujo-tailnet-proxy";
  dontUnpack = true;
  installPhase = ''
    mkdir -p "$out"
    ln -s ${config} "$out/Caddyfile"
    ln -s ${unit} "$out/mujo-tailnet-caddy.service"
    ln -s ${caddy-cloudflare}/bin/caddy "$out/caddy"
    printf '%s\n' '${tailscaleIPv4}' > "$out/tailscale-ip"
    printf '%s\n' '${routesDir}' > "$out/routes-dir"
  '';
}
