# No activation, credentials, certificate issuance, or Cloudflare requests:
# nix build --impure --no-link --file tests/spark/tailnet-proxy.nix
let
  flake = builtins.getFlake ("path:" + toString ../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-linux;
  inherit (pkgs) lib;
  bundle = flake.packages.aarch64-linux.tailnet-proxy;
  spark = flake.homeConfigurations.spark.config;
  personalConfig = spark.xdg.configFile."caddy/Caddyfile".text;
  tailnetctl = lib.findFirst (p: (p.name or "") == "tailnetctl") null spark.home.packages;
  settings = lib.importJSON ../../config/tailnet/spark.json;
in
assert lib.hasInfix "admin 127.0.0.1:2020" personalConfig;
assert lib.hasInfix "http://:18000" personalConfig;
assert lib.hasInfix "bind 127.0.0.1" personalConfig;
assert !(lib.hasInfix ":8000 {" personalConfig);
assert tailnetctl != null;
pkgs.runCommand "tailnet-proxy-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME" routes
  ${bundle}/caddy list-modules | grep -Fx dns.providers.cloudflare
  test "$(cat ${bundle}/routes-dir)" = ${settings.routesDir}
  test -x ${tailnetctl}/bin/tailnetctl

  # The production config must load with no routes and with a tailnetctl route.
  ${bundle}/caddy adapt --config ${bundle}/Caddyfile --adapter caddyfile > empty.json
  printf '%s\n' '@demo host demo.${settings.zone}' 'handle @demo {' \
    '	reverse_proxy 127.0.0.1:3001' '}' > routes/demo.caddy
  sed "s|${settings.routesDir}|$PWD/routes|" ${bundle}/Caddyfile > Caddyfile
  ${bundle}/caddy adapt --config Caddyfile --adapter caddyfile > routed.json

  python - <<'PY'
  import json
  from pathlib import Path

  def server(name):
      config = json.loads(Path(name).read_text())
      assert config['admin']['listen'] == 'unix//run/mujo-tailnet-caddy/admin.sock'
      dns = config['apps']['tls']['automation']['policies'][0]['issuers'][0]['challenges']['dns']
      assert dns['provider'] == {'name': 'cloudflare', 'api_token': '{env.CF_API_TOKEN}'}
      servers = config['apps']['http']['servers']
      assert len(servers) == 1
      server = next(iter(servers.values()))
      assert server['listen'] == ['${settings.tailscaleIPv4}:443']
      assert server['protocols'] == ['h1', 'h2']
      assert server['automatic_https']['disable_redirects'] is True
      [site] = server['routes']
      assert site['match'] == [{'host': ['*.${settings.zone}']}]
      return [r for r in site['handle'][0]['routes']]

  [fallback] = server('empty.json')
  assert fallback['handle'][0]['handler'] == 'subroute'
  routes = server('routed.json')
  assert len(routes) == 2
  assert routes[0]['match'] == [{'host': ['demo.${settings.zone}']}]
  assert 'match' not in routes[-1], 'fallback must be ordered last'
  unit = Path('${bundle}/mujo-tailnet-caddy.service').read_text()
  for required in [
      'DynamicUser=true', 'AmbientCapabilities=CAP_NET_BIND_SERVICE',
      'ProtectHome=true', 'ProtectSystem=strict', 'NoNewPrivileges=true',
      'LoadCredential=cloudflare-token:/etc/mujo-tailnet/cloudflare-token',
  ]:
      assert required in unit, required
  assert '--environ' not in unit
  PY
  touch "$out"
''
