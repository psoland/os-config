import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hosts/mac/install-rangr.sh"


class RangrInstallTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(
            prefix="rangr-test-",
            dir=os.environ.get("TMPDIR")
            or ("/tmp/opencode" if Path("/tmp/opencode").is_dir() else None),
        )
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.work = self.path / "temporary files"
        self.work.mkdir()
        self.log = self.path / "commands.jsonl"
        self.install_log = self.path / "installed"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TMPDIR": str(self.work),
            "COMMAND_LOG": str(self.log),
            "INSTALL_LOG": str(self.install_log),
            "NEXUS_REPO": "joexbayer/rangr",
        }
        self.stub(
            "uname",
            'import os, sys\n'
            'print(os.environ.get("TEST_OS", "Darwin") if sys.argv[1] == "-s" '
            'else os.environ.get("TEST_ARCH", "arm64"))\n',
        )
        # No real GitHub calls, macOS commands, or app installs are possible.
        self.stub(
            "gh",
            """import json, os, sys
from pathlib import Path

args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["release", "view"]:
    print(os.environ.get("TEST_TAG", "v0.1.11-test"))
    sys.exit(int(os.environ.get("TEST_VIEW_STATUS", "0")))
if args[:2] != ["release", "download"]:
    sys.exit("unexpected gh command")
destination = Path(args[args.index("--dir") + 1])
(destination / "install-release.sh").write_text(
    'set -eu\\n'
    'printf "%s\\\\n" "$@" "$NEXUS_REPO" "${NEXUS_INSTALL_DIR:-}" '
    '"${NEXUS_NO_CLI:-}" > "$INSTALL_LOG"\\n'
    'exit "${TEST_INSTALL_STATUS:-0}"\\n'
)
sys.exit(int(os.environ.get("TEST_DOWNLOAD_STATUS", "0")))
""",
        )

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n{body}")
        path.chmod(0o755)

    def run_script(self, *args, status=0):
        result = subprocess.run(
            ["bash", str(SCRIPT), *args],
            env=self.env,
            cwd=self.path,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, status, result.stderr)
        self.assertEqual(list(self.work.iterdir()), [], "temporary files leaked")
        return result

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_latest_is_resolved_once_and_installer_uses_same_tag(self):
        self.run_script()
        commands = self.commands()
        self.assertEqual(
            commands[0],
            ["release", "view", "--repo", "joexbayer/rangr",
             "--json", "tagName", "--jq", ".tagName"],
        )
        self.assertEqual(len(commands), 2)
        self.assertEqual(
            commands[1][:-1],
            ["release", "download", "v0.1.11-test", "--repo",
             "joexbayer/rangr", "--pattern", "install-release.sh", "--dir"],
        )
        self.assertEqual(
            self.install_log.read_text().splitlines(),
            ["v0.1.11-test", "joexbayer/rangr", "", ""],
        )

    def test_explicit_tag_skips_latest_and_preserves_overrides(self):
        self.env.update(
            NEXUS_REPO="example/rangr",
            NEXUS_INSTALL_DIR="/custom applications",
            NEXUS_NO_CLI="1",
        )
        self.run_script("v0.1.10-pinned")
        commands = self.commands()
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][2:5], ["v0.1.10-pinned", "--repo", "example/rangr"])
        self.assertEqual(
            self.install_log.read_text().splitlines(),
            ["v0.1.10-pinned", "example/rangr", "/custom applications", "1"],
        )

    def test_help_has_no_side_effects(self):
        self.env["TEST_OS"] = "Linux"
        self.assertIn("Usage:", self.run_script("--help").stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_arguments_have_no_side_effects(self):
        for args in [("--unknown",), ("v1", "v2")]:
            with self.subTest(args=args):
                self.run_script(*args, status=1)
                self.assertFalse(self.log.exists())

    def test_unsupported_platforms_have_no_side_effects(self):
        for system, arch in [("Linux", "arm64"), ("Linux", "aarch64"), ("Darwin", "x86_64")]:
            with self.subTest(system=system, arch=arch):
                self.env.update(TEST_OS=system, TEST_ARCH=arch)
                self.run_script(status=1)
                self.assertFalse(self.log.exists())

    def test_missing_gh_has_actionable_error(self):
        # A private PATH allows uname, but cannot fall through to a real gh.
        self.env["PATH"] = str(self.bin)
        (self.bin / "gh").unlink()
        bash = shutil.which("bash")
        result = subprocess.run(
            [bash, str(SCRIPT)], env=self.env, capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("gh auth login", result.stderr)
        self.assertFalse(self.log.exists())

    def test_failed_latest_lookup_stops_before_download(self):
        self.env["TEST_VIEW_STATUS"] = "4"
        self.run_script(status=4)
        self.assertEqual(len(self.commands()), 1)
        self.assertFalse(self.install_log.exists())

    def test_empty_or_option_like_latest_tag_is_rejected(self):
        for tag in ["", "--invalid"]:
            with self.subTest(tag=tag):
                self.env["TEST_TAG"] = tag
                self.run_script(status=1)
                self.assertFalse(self.install_log.exists())
                self.log.unlink()

    def test_failed_partial_download_is_never_executed(self):
        self.env["TEST_DOWNLOAD_STATUS"] = "5"
        self.run_script(status=5)
        self.assertFalse(self.install_log.exists())

    def test_installer_failure_propagates_and_cleans_up(self):
        self.env["TEST_INSTALL_STATUS"] = "7"
        self.run_script(status=7)
        self.assertTrue(self.install_log.exists())


if __name__ == "__main__":
    unittest.main()
