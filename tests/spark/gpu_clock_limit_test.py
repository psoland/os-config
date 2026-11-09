import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "hosts/spark"
SERVICE = "spark-gpu-clock-limit.service"


class GpuClockLimitTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(
            prefix="spark-clock-test-", dir="/tmp/opencode"
        )
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.units = self.path / "units"
        self.units.mkdir()
        self.log = self.path / "commands"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "COMMAND_LOG": str(self.log),
            "TMPDIR": str(self.path),
        }
        self.stub("id", 'echo "${TEST_UID:-0}"')
        self.stub("uname", "echo Linux")
        self.stub("systemctl", 'echo "systemctl $*" >> "$COMMAND_LOG"')
        self.stub(
            "nvidia-smi",
            'echo "nvidia-smi $*" >> "$COMMAND_LOG"\n'
            'if [ "$1" = --query-gpu=name ]; then\n'
            '  echo "${TEST_GPU:-NVIDIA GB10}"\n'
            'elif [ "$1" = -lgc ]; then\n'
            '  exit "${TEST_CLOCK_FAILURE:-0}"\n'
            "fi",
        )
        # Only run a sandboxed copy: never access the real driver or system units.
        self.script = self.path / "gpu-clock-limit.sh"
        self.script.write_text(
            (SOURCE / self.script.name).read_text()
            .replace("/usr/bin/nvidia-smi", str(self.bin / "nvidia-smi"))
            .replace("/etc/systemd/system", str(self.units))
        )
        shutil.copyfile(SOURCE / SERVICE, self.path / SERVICE)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n")
        path.chmod(0o755)

    def run_script(self, *args, success=True):
        result = subprocess.run(
            ["bash", str(self.script), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_default_install_and_reinstall_with_custom_clock(self):
        for args, maximum in [((), 2200), (("install", "2000"), 2000)]:
            self.run_script(*args)
            unit = self.units / SERVICE
            text = unit.read_text()
            self.assertIn(f"ExecStart=/usr/bin/nvidia-smi -lgc 0,{maximum}", text)
            self.assertNotIn("@MAX_MHZ@", text)
            self.assertEqual(unit.stat().st_mode & 0o777, 0o644)
            commands = self.log.read_text()
            self.assertLess(
                commands.index(f"nvidia-smi -lgc 0,{maximum}"),
                commands.rindex("systemctl daemon-reload"),
            )
            self.assertIn(f"systemctl enable {SERVICE}", commands)
            self.assertIn(f"systemctl restart {SERVICE}", commands)

    def test_invalid_arguments_have_no_side_effects(self):
        for args in [
            ("install", "0"),
            ("install", "10001"),
            ("install", "02200"),
            ("install", "2200; touch bad"),
            ("install", "2200", "extra"),
            ("remove", "extra"),
            ("unknown",),
        ]:
            with self.subTest(args=args):
                self.run_script(*args, success=False)
                self.assertFalse(self.log.exists())
                self.assertFalse((self.units / SERVICE).exists())

    def test_requires_root(self):
        self.env["TEST_UID"] = "1000"
        self.run_script(success=False)
        self.assertFalse(self.log.exists())

    def test_wrong_gpu_leaves_system_untouched(self):
        self.env["TEST_GPU"] = "NVIDIA RTX 4090"
        self.run_script(success=False)
        self.assertFalse((self.units / SERVICE).exists())
        self.assertNotIn("systemctl", self.log.read_text())
        self.assertNotIn("-lgc", self.log.read_text())

    def test_unsupported_clock_preserves_existing_unit(self):
        unit = self.units / SERVICE
        unit.write_text("existing unit\n")
        self.env["TEST_CLOCK_FAILURE"] = "3"
        self.run_script(success=False)
        self.assertEqual(unit.read_text(), "existing unit\n")
        self.assertNotIn("systemctl", self.log.read_text())

    def test_remove_is_repeatable_and_resets_clocks(self):
        self.run_script()
        self.run_script("remove")
        self.assertFalse((self.units / SERVICE).exists())
        commands = self.log.read_text()
        self.assertIn(f"systemctl disable --now {SERVICE}", commands)
        self.assertIn("nvidia-smi -rgc", commands)
        self.run_script("remove")

    @unittest.skipUnless(shutil.which("systemd-analyze"), "systemd-analyze is required")
    def test_systemd_unit_is_valid(self):
        self.run_script()
        unit = self.units / SERVICE
        unit.write_text(unit.read_text().replace("/usr/bin/nvidia-smi", "/bin/true"))
        result = subprocess.run(
            ["systemd-analyze", "verify", str(unit)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
