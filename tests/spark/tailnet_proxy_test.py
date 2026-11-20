"""Sandboxed tests: no real units, credentials, sudo, or network changes.

python3 -m unittest discover -s tests/spark -p 'tailnet_proxy_test.py'
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="tailnet-test-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.log = self.path / "commands"
        self.log.touch()
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "COMMAND_LOG": str(self.log),
            "ACTIVE_MARKER": str(self.path / "active"),
        }

    def stub(self, name, body):
        executable = self.bin / name
        executable.write_text(f"#!/bin/bash\nset -eu\n{body}\n")
        executable.chmod(0o755)

    def run_script(self, *args, success=True):
        result = subprocess.run(
            ["bash", str(self.script), *args], env=self.env,
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result


class InstallerTests(Sandbox):
    def setUp(self):
        super().setUp()
        self.units = self.path / "units"
        self.units.mkdir()
        self.config = self.path / "config"
        self.config.mkdir()
        self.token = self.config / "cloudflare-token"
        self.token.write_text("test-only-not-a-real-token")
        self.token.chmod(0o600)
        self.roots = self.path / "gcroots"
        self.roots.mkdir()
        self.store = self.path / "store"
        self.store.mkdir()
        self.routes = self.path / "routes"
        self.bundle = self.store / "test-mujo-tailnet-proxy"
        self.bundle.mkdir()
        for name in ["Caddyfile", "caddy"]:
            (self.bundle / name).write_text("test fixture\n")
        (self.bundle / "mujo-tailnet-caddy.service").write_text(
            "# Managed by dotfiles/packages/tailnet-proxy.nix\ntest fixture\n"
        )
        (self.bundle / "tailscale-ip").write_text("100.127.53.67\n")
        (self.bundle / "routes-dir").write_text(f"{self.routes}\n")
        self.stub("uname", "echo Linux")
        self.stub("id", 'echo "${TEST_UID:-0}"')
        self.stub("stat", 'echo "${TEST_STAT:-0:600}"')
        self.stub("tailscale", '''
if [ "$1" = ip ]; then echo "${TEST_IP:-100.127.53.67}"; exit; fi
echo "${TEST_SERVE:-{\\}}"
''')
        self.stub("ss", '''
if [ "${TEST_SS_FAILURE:-0}" != 0 ]; then exit "$TEST_SS_FAILURE"; fi
[ "${TEST_OCCUPIED:-0}" = 0 ] || echo LISTEN
''')
        self.stub("systemd-analyze", 'echo "verify $*" >> "$COMMAND_LOG"\nexit "${TEST_VERIFY_FAILURE:-0}"')
        self.stub("systemctl", '''
echo "systemctl $*" >> "$COMMAND_LOG"
if [ "$1" = is-active ]; then test -f "$ACTIVE_MARKER"; fi
if [ "$1" = restart ]; then touch "$ACTIVE_MARKER"; fi
if [ "$1" = disable ]; then rm -f "$ACTIVE_MARKER"; fi
''')
        source = (ROOT / "hosts/spark/tailnet-proxy.sh").read_text()
        self.script = self.path / "installer.sh"
        self.script.write_text(source
            .replace("/etc/mujo-tailnet", str(self.config))
            .replace("/etc/systemd/system", str(self.units))
            .replace("/nix/var/nix/gcroots", str(self.roots))
            .replace("/nix/store", str(self.store)))

    def run_script(self, *args, success=True):
        result = super().run_script(*args, success=success)
        self.assertNotIn("test-only-not-a-real-token", result.stdout + result.stderr)
        return result

    def assert_not_installed(self):
        self.assertFalse((self.units / "mujo-tailnet-caddy.service").exists())
        self.assertFalse((self.roots / "mujo-tailnet-proxy").exists())

    def test_install_reinstall_and_remove(self):
        for _ in range(2):
            self.run_script("install", str(self.bundle))
            self.assertEqual((self.roots / "mujo-tailnet-proxy").resolve(), self.bundle)
            self.assertEqual((self.units / "mujo-tailnet-caddy.service").stat().st_mode & 0o777, 0o644)
            self.assertTrue(self.routes.is_dir())
        commands = self.log.read_text()
        self.assertLess(commands.index("verify"), commands.index("systemctl daemon-reload"))
        self.assertIn("systemctl restart mujo-tailnet-caddy.service", commands)
        (self.routes / "keep.caddy").write_text("route")
        self.run_script("remove")
        self.assert_not_installed()
        self.assertTrue(self.token.exists())
        self.assertTrue((self.routes / "keep.caddy").exists())

    def test_bad_arguments(self):
        for args in [(), ("bogus",), ("install",), ("install", str(self.bundle), "extra"), ("remove", "x")]:
            self.run_script(*args, success=False)
            self.assert_not_installed()

    def test_requires_root(self):
        self.env["TEST_UID"] = "1000"
        self.run_script("install", str(self.bundle), success=False)
        self.assert_not_installed()

    def test_missing_or_symlinked_credentials(self):
        self.token.unlink()
        self.run_script("install", str(self.bundle), success=False)
        other = self.path / "other-token"
        other.write_text("test-only-not-a-real-token")
        self.token.symlink_to(other)
        self.run_script("install", str(self.bundle), success=False)
        self.assert_not_installed()

    def test_insecure_credentials(self):
        for stat in ["1000:600", "0:644", "0:400"]:
            self.env["TEST_STAT"] = stat
            self.run_script("install", str(self.bundle), success=False)
            self.assert_not_installed()

    def test_wrong_host(self):
        self.env["TEST_IP"] = "100.100.1.1"
        self.run_script("install", str(self.bundle), success=False)
        self.assert_not_installed()

    def test_tailscale_serve_owns_443(self):
        self.env["TEST_SERVE"] = '{"TCP":{"443":{"HTTPS":true}}}'
        result = self.run_script("install", str(self.bundle), success=False)
        self.assertIn("Tailscale Serve", result.stderr)
        self.assert_not_installed()

    def test_foreign_https_listener(self):
        self.env["TEST_OCCUPIED"] = "1"
        self.run_script("install", str(self.bundle), success=False)
        self.assert_not_installed()

    def test_failed_listener_inspection(self):
        self.env["TEST_SS_FAILURE"] = "1"
        result = self.run_script("install", str(self.bundle), success=False)
        self.assertIn("Could not inspect TCP port 443", result.stderr)
        self.assert_not_installed()

    def test_failed_verification_preserves_existing_unit(self):
        unit = self.units / "mujo-tailnet-caddy.service"
        previous = "# Managed by dotfiles/packages/tailnet-proxy.nix\nprevious unit"
        unit.write_text(previous)
        self.env["TEST_VERIFY_FAILURE"] = "1"
        self.run_script("install", str(self.bundle), success=False)
        self.assertEqual(unit.read_text(), previous)
        self.assertNotIn("daemon-reload", self.log.read_text())

    def test_refuses_unowned_unit(self):
        unit = self.units / "mujo-tailnet-caddy.service"
        unit.write_text("foreign unit")
        self.run_script("install", str(self.bundle), success=False)
        self.run_script("remove", success=False)
        self.assertEqual(unit.read_text(), "foreign unit")

    def test_refuses_foreign_gc_root(self):
        root = self.roots / "mujo-tailnet-proxy"
        root.symlink_to(self.store / "unrelated-service")
        self.run_script("install", str(self.bundle), success=False)
        self.assertEqual(os.readlink(root), str(self.store / "unrelated-service"))


@unittest.skipUnless(shutil.which("caddy"), "caddy is needed to validate routes")
class TailnetctlTests(Sandbox):
    def setUp(self):
        super().setUp()
        self.routes = self.path / "routes"
        self.routes.mkdir()
        self.script = ROOT / "hosts/spark/services/tailnet/tailnetctl.sh"
        self.env.update(TAILNET_ZONES="mujo.no example.com", TAILNET_ROUTES_DIR=str(self.routes))
        # sudo runs the command unprivileged so writes land in the sandbox.
        self.stub("sudo", 'echo "sudo $*" >> "$COMMAND_LOG"\nexec "$@"')
        self.stub("ss", '[ "${TEST_LISTENING:-0}" = 0 ] || echo LISTEN')
        self.stub("systemctl", '''
echo "systemctl $*" >> "$COMMAND_LOG"
if [ "$1" = is-active ]; then exit "${TEST_INACTIVE:-0}"; fi
if [ "$1" = reload ]; then exit "${TEST_RELOAD_FAILURE:-0}"; fi
''')
        (self.path / "active").touch()

    def test_add_list_and_remove(self):
        result = self.run_script("add", "agents", "3000")
        self.assertIn("https://agents.mujo.no -> 127.0.0.1:3000", result.stdout)
        self.assertIn("nothing is listening on port 3000", result.stderr)
        route = (self.routes / "agents.mujo.no.caddy").read_text()
        self.assertIn("@agents_mujo_no host agents.mujo.no", route)
        self.assertIn("reverse_proxy 127.0.0.1:3000", route)
        self.assertIn("sudo systemctl reload mujo-tailnet-caddy.service", self.log.read_text())

        self.env["TEST_LISTENING"] = "1"
        self.run_script("add", "benchmark", "3001")
        listing = self.run_script("ls").stdout
        self.assertIn("https://agents.mujo.no", listing)
        self.assertRegex(listing, r"benchmark\.mujo\.no\s+127\.0\.0\.1:3001\s+up")

        self.run_script("rm", "agents")
        self.assertFalse((self.routes / "agents.mujo.no.caddy").exists())
        self.assertTrue((self.routes / "benchmark.mujo.no.caddy").exists())

    def test_readding_same_route_is_a_noop(self):
        self.run_script("add", "agents", "3000")
        self.log.write_text("")
        result = self.run_script("add", "agents", "3000")
        self.assertIn("already routes", result.stdout)
        self.assertNotIn("reload", self.log.read_text())

    def test_changing_port_replaces_route(self):
        self.run_script("add", "agents", "3000")
        self.run_script("add", "agents", "4000")
        self.assertIn("127.0.0.1:4000", (self.routes / "agents.mujo.no.caddy").read_text())

    def test_other_configured_domain(self):
        result = self.run_script("add", "agents.example.com", "3002")
        self.assertIn("https://agents.example.com -> 127.0.0.1:3002", result.stdout)
        self.run_script("add", "agents", "3000")
        self.assertTrue((self.routes / "agents.example.com.caddy").exists())
        self.assertTrue((self.routes / "agents.mujo.no.caddy").exists())
        self.assertIn("https://agents.example.com", self.run_script("ls").stdout)
        self.run_script("rm", "agents.example.com")
        self.assertFalse((self.routes / "agents.example.com.caddy").exists())
        self.assertTrue((self.routes / "agents.mujo.no.caddy").exists())

    def test_rejects_bad_input_without_changes(self):
        for args in [
            ("add", "Agents", "3000"), ("add", "a.b", "3000"), ("add", "-x", "3000"),
            ("add", "x.other.org", "3000"), ("add", "a.b.mujo.no", "3000"),
            ("add", "mujo.no", "3000"), ("add", ".mujo.no", "3000"),
            ("add", "x" * 64, "3000"), ("add", "ok", "0"), ("add", "ok", "65536"),
            ("add", "ok", "80; respond"), ("add", "ok"), ("rm", "missing"), ("bogus",),
        ]:
            self.run_script(*args, success=False)
        self.assertEqual(list(self.routes.iterdir()), [])
        self.assertNotIn("sudo", self.log.read_text())

    def test_invalid_existing_route_blocks_changes(self):
        (self.routes / "broken.caddy").write_text("not_a_directive 1\n")
        self.run_script("add", "agents", "3000", success=False)
        self.assertFalse((self.routes / "agents.mujo.no.caddy").exists())

    def test_failed_reload_restores_previous_route(self):
        self.run_script("add", "agents", "3000")
        previous = (self.routes / "agents.mujo.no.caddy").read_text()
        self.env["TEST_RELOAD_FAILURE"] = "1"
        self.run_script("add", "agents", "4000", success=False)
        self.assertEqual((self.routes / "agents.mujo.no.caddy").read_text(), previous)
        self.run_script("add", "new", "5000", success=False)
        self.assertFalse((self.routes / "new.mujo.no.caddy").exists())

    def test_inactive_proxy_still_records_route(self):
        self.env["TEST_INACTIVE"] = "3"
        result = self.run_script("add", "agents", "3000")
        self.assertIn("not running", result.stderr)
        self.assertTrue((self.routes / "agents.mujo.no.caddy").exists())

    def test_requires_installed_routes_dir(self):
        self.routes.rmdir()
        result = self.run_script("ls", success=False)
        self.assertIn("install the proxy first", result.stderr)


if __name__ == "__main__":
    unittest.main()
