import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "config/tmux/status.py"
spec = importlib.util.spec_from_file_location("status", SCRIPT)
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class StatusTests(unittest.TestCase):
    def test_percentage_validation(self):
        for output, expected in [(" 9.9%\n", 9.9), ("0.0%", 0), ("100.0%", 100)]:
            self.assertEqual(status.cpu_usage(output), expected)
        for output in ("", "nan%", "inf%", "-1%", "100.1%", "1%#[blink]", "1%\n2%"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                status.cpu_usage(output)

    def test_save_policy_requires_continuum_timestamp_and_enabled_interval(self):
        self.assertTrue(status.save_due("15", "100", 1000))
        for interval, stamp, now in [
            ("15", "100", 999),
            ("0", "100", 1000),
            ("-1", "100", 1000),
            ("15", "", 1000),
            ("15", "0", 1000),
            ("", "100", 1000),
        ]:
            self.assertFalse(status.save_due(interval, stamp, now))

    def test_lock_is_per_socket_and_server_and_released_on_exit(self):
        with (
            tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory,
            patch.dict(os.environ, {"XDG_CACHE_HOME": directory}),
        ):
            with status.locked("/socket", 123) as first:
                self.assertTrue(first)
                with status.locked("/socket", 123) as duplicate:
                    self.assertFalse(duplicate)
                with status.locked("/socket", 124) as replacement:
                    self.assertTrue(replacement)
            with status.locked("/socket", 123) as restarted:
                self.assertTrue(restarted)


@unittest.skipUnless(shutil.which("tmux"), "tmux is required")
class StatusIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(
            prefix="tmux-status-test-", dir="/tmp/opencode"
        )
        self.path = Path(self.directory.name)
        self.socket = str(self.path / "socket with spaces")
        self.env = {**os.environ, "XDG_CACHE_HOME": str(self.path / "cache")}
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.pid = self.tmux(
            "-f", "/dev/null", "new-session", "-d", "-P", "-F", "#{pid}", "sleep 300"
        )
        self.cpu = self.path / "cpu sampler"
        self.save = self.path / "autosave"
        self.cpu.write_text("#!/bin/sh\nprintf '9.9%%\\n'\n")
        self.save.write_text(f"#!/bin/sh\nprintf saved >> '{self.path / 'saved'}'\n")
        self.cpu.chmod(0o755)
        self.save.chmod(0o755)
        self.updater = status.Updater(
            self.socket, self.pid, str(self.cpu), str(self.save)
        )
        self.worker = None

    def tearDown(self):
        subprocess.run(
            ["tmux", "-S", self.socket, "kill-server"],
            env=self.env,
            capture_output=True,
            check=False,
        )
        if self.worker:
            try:
                self.worker.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                self.worker.terminate()
                self.worker.communicate(timeout=5)
        self.directory.cleanup()

    def tmux(self, *args):
        return subprocess.check_output(
            ["tmux", "-S", self.socket, *args], env=self.env, text=True
        ).rstrip("\n")

    def option(self, name):
        return self.tmux("show-options", "-gqv", name)

    def worker_command(self):
        return [
            sys.executable,
            "-B",
            str(SCRIPT),
            "--socket",
            self.socket,
            "--server-pid",
            self.pid,
            "--cpu-script",
            str(self.cpu),
            "--continuum-script",
            str(self.save),
            "--interval",
            "0.05",
        ]

    def test_samples_target_socket_and_skips_unchanged_writes(self):
        self.assertEqual(self.updater.env["TMUX"], f"{self.socket},{self.pid},0")
        self.assertTrue(self.updater.tick())
        self.assertEqual(self.option("@status_cpu_usage"), "9.9")
        self.assertEqual(self.option("@status_cpu_text"), "  9.9%")
        self.assertFalse((self.path / "saved").exists())
        with patch.object(self.updater, "tmux", wraps=self.updater.tmux) as calls:
            self.updater.tick()
            self.assertFalse(
                any(call.args[0] == "set-option" for call in calls.call_args_list)
            )

    def test_one_sample_updates_fixed_width_text_and_number(self):
        for value in (0, 9.9, 10, 80, 100):
            self.updater.publish(value)
            self.assertEqual(len(self.option("@status_cpu_text")), 6)
            self.assertEqual(float(self.option("@status_cpu_usage")), value)

    def test_invalid_sample_displays_placeholder_not_old_usage(self):
        self.updater.publish(90)
        self.cpu.write_text("#!/bin/sh\nprintf 'bad sample'\n")
        self.updater.tick()
        self.assertEqual(self.option("@status_cpu_text"), " --.-%")
        self.assertEqual(self.option("@status_cpu_usage"), "0")

    def test_autosave_runs_only_when_enabled_and_due(self):
        self.tmux("set-option", "-g", "@continuum-save-interval", "15")
        self.updater.tick()
        self.assertFalse((self.path / "saved").exists())
        self.tmux(
            "set-option", "-g", "@continuum-save-last-timestamp", str(int(time.time()))
        )
        self.updater.tick()
        self.assertFalse((self.path / "saved").exists())
        self.tmux("set-option", "-g", "@continuum-save-last-timestamp", "1")
        self.updater.tick()
        self.assertEqual((self.path / "saved").read_text(), "saved")
        self.tmux("set-option", "-g", "@continuum-save-interval", "0")
        self.updater.tick()
        self.assertEqual((self.path / "saved").read_text(), "saved")

    def test_wrong_server_is_not_sampled_or_modified(self):
        self.updater.server_pid = "0"
        self.assertFalse(self.updater.tick())
        self.assertEqual(self.option("@status_cpu_text"), "")

    def test_worker_is_singleton_and_exits_when_server_disappears(self):
        self.worker = subprocess.Popen(
            self.worker_command(),
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while not self.option("@status_cpu_text"):
            self.assertIsNone(self.worker.poll())
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.02)
        duplicate = subprocess.run(
            self.worker_command(),
            env=self.env,
            capture_output=True,
            timeout=5,
            check=False,
        )
        self.assertEqual(duplicate.returncode, 0, duplicate.stderr)
        self.assertIsNone(self.worker.poll())
        self.tmux("kill-server")
        _stdout, stderr = self.worker.communicate(timeout=5)
        self.assertEqual(self.worker.returncode, 0, stderr)

    def test_real_theme_has_no_shell_jobs_and_keeps_dynamic_cpu_colours(self):
        installed = Path.home() / ".config/tmux/tmux.conf"
        match = re.search(
            r"run-shell (\S+/catppuccin)/catppuccin\.tmux",
            installed.read_text() if installed.exists() else "",
        )
        if not match or not Path(match[1]).is_dir():
            self.skipTest("an installed Catppuccin plugin is required")
        plugin = Path(match[1])
        module = (ROOT / "modules/home/programs/tmux.nix").read_text()
        theme = (
            module.split("plugin = catppuccin;", 1)[1]
            .split("extraConfig = ''", 1)[1]
            .split("'';", 1)[0]
        )
        config = self.path / "status.conf"
        config.write_text(theme)
        self.tmux("source-file", str(config))
        for name in ("catppuccin_options_tmux.conf", "catppuccin_tmux.conf"):
            self.tmux("source-file", str(plugin / name))
        bar = module.split("# --- Cached status bar ---", 1)[1].split("'';", 1)[0]
        config.write_text(
            "\n".join(
                line for line in bar.splitlines() if "${statusHelper}" not in line
            )
        )
        self.tmux("source-file", str(config))
        for value, colour in [(9.9, "#313244"), (80, "#f38ba8"), (10, "#313244")]:
            self.updater.publish(value)
            expanded = self.tmux("display-message", "-p", "#{E:status-right}")
            self.assertNotIn("#(", self.option("status-right") + expanded)
            self.assertNotIn("#{cpu_", expanded)
            self.assertIn(f"bg={colour}] {value:5.1f}%", expanded)
        self.assertIn("agents:", expanded)
        directory = self.path / "parent ' spaces" / "leaf $(no-shell)"
        directory.mkdir(parents=True)
        pane = self.tmux(
            "new-window",
            "-d",
            "-c",
            str(directory),
            "-P",
            "-F",
            "#{pane_id}",
            "sleep 300",
        )
        self.assertEqual(
            self.tmux(
                "display-message", "-p", "-t", pane, "#{E:@catppuccin_directory_text}"
            ),
            "parent ' spaces/leaf $(no-shell)",
        )
