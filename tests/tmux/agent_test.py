import concurrent.futures
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "config/tmux/agent.py"
spec = importlib.util.spec_from_file_location("agent", SCRIPT)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


@unittest.skipUnless(shutil.which("tmux"), "tmux is required")
class TrackerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(
            prefix="tmux-agent-test-",
            dir="/tmp/opencode" if Path("/tmp/opencode").is_dir() else None,
        )
        self.path = Path(self.directory.name)
        self.socket = str(self.path / "socket with spaces")
        self.env = {**os.environ, "XDG_CACHE_HOME": str(self.path / "cache")}
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.a, self.pane = self.tmux(
            "-f",
            "/dev/null",
            "new-session",
            "-d",
            "-s",
            "short",
            "-P",
            "-F",
            "#{session_id} #{pane_id}",
            "sleep 300",
        ).split()
        self.b, self.other = self.tmux(
            "new-session",
            "-d",
            "-s",
            "a-much-longer-session",
            "-P",
            "-F",
            "#{session_id} #{pane_id}",
            "sleep 300",
        ).split()
        self.client = None

    def tearDown(self):
        subprocess.run(
            ["tmux", "-S", self.socket, "kill-server"],
            env=self.env,
            capture_output=True,
            check=False,
        )
        if self.client:
            self.client.communicate(timeout=5)
        self.directory.cleanup()

    def tmux(self, *args):
        return subprocess.check_output(
            ["tmux", "-S", self.socket, *args], env=self.env, text=True
        ).rstrip("\n")

    def helper(self, *args):
        return subprocess.check_output(
            [sys.executable, str(SCRIPT), "--socket", self.socket, *args],
            env=self.env,
            text=True,
        )

    def state(self, value, source="first", pane=None, *extra):
        self.helper(
            "state", value, "--pane", pane or self.pane, "--source", source, *extra
        )

    def status(self, session=None):
        return self.tmux("show-options", "-qv", "-t", session or self.a, agent.STATUS)

    def running_count(self, session=None):
        return self.tmux(
            "show-options", "-qv", "-t", session or self.a, agent.RUNNING_COUNT
        )

    def records(self, pane=None):
        return json.loads(
            self.tmux("show-options", "-pv", "-t", pane or self.pane, agent.RECORDS)
        )

    def configure(self, status_bar=False):
        # Parse the actual module's extraConfig, substituting only its Nix helper
        # path. This tests real bindings/hooks/styles, not a test-only equivalent.
        executable = self.path / "bin/tmux-agent"
        executable.parent.mkdir(exist_ok=True)
        executable.write_text(
            f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(SCRIPT))} "$@"\n'
        )
        executable.chmod(0o755)
        module = (ROOT / "modules/home/programs/tmux.nix").read_text()
        config = module.split("extraConfig = ''", 1)[1].split("'';", 1)[0]
        config = config.replace("${agentHelper}", str(self.path))
        if status_bar:
            for plugin in ("catppuccin", "cpu"):
                config += (
                    module.split(f"plugin = {plugin};", 1)[1]
                    .split("extraConfig = ''", 1)[1]
                    .split("'';", 1)[0]
                )
        target = self.path / "tmux.conf"
        target.write_text(config)
        self.tmux("source-file", str(target))

    def attach(self, session=None):
        self.client = subprocess.Popen(
            [
                "tmux",
                "-S",
                self.socket,
                "-C",
                "attach-session",
                "-t",
                session or self.a,
            ],
            env=self.env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.wait(lambda: bool(self.tmux("list-clients")))

    def wait(self, condition):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.02)
        self.fail("timed out waiting for tmux hook")

    def test_priority_and_per_agent_state(self):
        self.state("running")
        self.assertEqual(self.status(), "running")
        self.state("finished", "second")
        self.assertEqual(self.status(), "finished")
        self.state("needs-input", "third")
        self.assertEqual(self.status(), "needs-input")
        self.state("running", "first")
        self.assertEqual(self.status(), "needs-input")
        self.helper("remove", "--pane", self.pane, "--source", "third")
        self.assertEqual(self.status(), "finished")
        self.helper("acknowledge", self.a)
        self.assertEqual(self.status(), "running")
        self.assertEqual(self.records()["second"]["state"], "finished")
        self.assertFalse(self.records()["second"]["unread"])

    def test_running_count_is_session_local_and_survives_acknowledgement(self):
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.state("running", "one")
        self.state("running", "two", split)
        self.state("running", "other", self.other)
        self.assertEqual(self.running_count(), "2")
        self.assertEqual(self.running_count(self.b), "1")
        self.state("needs-input", "two", split)
        self.helper("acknowledge", self.a)
        self.assertEqual(self.running_count(), "1")
        self.state("finished", "one")
        self.assertEqual(self.running_count(), "0")
        self.assertEqual(self.running_count(self.b), "1")

    def test_status_bar_order_and_session_colour(self):
        for option, value in {
            "@catppuccin_status_cpu": "cpu",
            "@catppuccin_status_directory": "folder",
            "@catppuccin_status_session": "session",
            "@catppuccin_status_host": "host",
            "@thm_lavender": "#b4befe",
        }.items():
            self.tmux("set-option", "-g", option, value)
        self.configure(status_bar=True)
        bar = self.tmux("display-message", "-p", "-t", self.a, "#{E:status-right}")
        positions = [
            bar.index(label) for label in ("agents:", "cpu", "folder", "session", "host")
        ]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(
            self.tmux(
                "display-message", "-p", "-t", self.a, "#{E:@catppuccin_session_color}"
            ),
            "#b4befe",
        )

    def test_status_bar_count_and_colours_follow_session_state(self):
        self.configure(status_bar=True)
        for option, value in {
            "@thm_overlay_0": "#6c7086",
            "@thm_crust": "#11111b",
            "@thm_fg": "#cdd6f4",
            "@catppuccin_status_module_text_bg": "#313244",
            "@catppuccin_status_left_separator": "\ue0b6",
            "@catppuccin_status_right_separator": " ",
        }.items():
            self.tmux("set-option", "-g", option, value)

        def bar(session=None):
            return self.tmux(
                "display-message", "-p", "-t", session or self.a, "#{E:status-right}"
            )

        self.assertIn("agents: 0", bar())
        self.assertIn("bg=#a6e3a1]●", bar())
        self.state("running", "one")
        self.state("running", "two")
        self.assertIn("agents: 2", bar())
        self.assertIn("bg=#a6e3a1]●", bar())
        self.assertIn("agents: 0", bar(self.b))
        self.state("finished", "two")
        self.assertIn("agents: 1", bar())
        self.assertIn("bg=#a6e3a1]●", bar())
        self.state("needs-input", "three")
        self.assertIn("bg=#89b4fa]●", bar())
        self.helper("acknowledge", self.a)
        self.assertIn("agents: 1", bar())
        self.assertIn("bg=#a6e3a1]●", bar())

    def test_acknowledgement_is_scoped_and_new_events_reappear(self):
        self.state("finished", "one")
        self.state("needs-input", "two", self.other)
        self.helper("acknowledge", self.a)
        self.assertEqual(self.status(), "")
        self.assertEqual(self.status(self.b), "needs-input")
        self.state("needs-input", "one", self.pane, "--event", "new-request")
        self.assertEqual(self.status(), "needs-input")

    def test_multiple_panes_contribute_and_visit_acknowledges_all(self):
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.state("finished", "first")
        self.state("needs-input", "second", split)
        self.assertEqual(self.status(), "needs-input")
        self.helper("acknowledge", self.a)
        self.assertEqual(self.status(), "")
        self.assertFalse(self.records()["first"]["unread"])
        self.assertFalse(self.records(split)["second"]["unread"])
        self.assertEqual(self.records(split)["second"]["state"], "needs-input")

    def test_replayed_and_delayed_events_do_not_reassert_attention(self):
        self.state("finished", "one", self.pane, "--event", "done")
        self.helper("acknowledge", self.a)
        self.state("finished", "one", self.pane, "--event", "done")
        self.assertEqual(self.status(), "")
        self.state("needs-input", "another", self.pane, "--at", "1")
        self.assertEqual(self.status(), "")
        self.state("running", "one", self.pane, "--at", "1")
        self.assertEqual(self.records()["one"]["state"], "finished")

    def test_parallel_events_are_not_lost(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda i: self.state("finished", f"agent-{i}"), range(12)))
        self.assertEqual(len(self.records()), 12)
        self.assertEqual(self.status(), "finished")

    def test_dead_clients_and_closed_panes_are_pruned(self):
        process = subprocess.Popen(["sleep", "1"])
        self.state("running", "dead", self.pane, "--pid", str(process.pid))
        process.wait(timeout=5)
        self.helper("refresh")
        self.assertEqual(self.records(), {})
        self.assertEqual(self.status(), "")
        self.assertEqual(self.running_count(), "0")
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.state("finished", "split-agent", split)
        self.tmux("kill-pane", "-t", split)
        self.helper("refresh")
        self.assertEqual(self.status(), "")

    def test_moving_an_agent_window_updates_both_sessions(self):
        self.state("needs-input")
        self.tmux("move-window", "-s", f"{self.a}:0", "-t", self.b)
        self.helper("refresh")
        self.assertEqual(self.status(self.b), "needs-input")

    def test_actual_hooks_acknowledge_attach_and_switch_without_replacing_ts(self):
        self.configure()
        self.tmux(
            "set-hook",
            "-t",
            self.a,
            "client-attached",
            f"set-option -t {self.a} @ts_resize_ran 1",
        )
        self.state("finished")
        self.state("needs-input", "other-agent", self.other)
        self.attach()
        self.wait(lambda: self.status() == "")
        self.assertEqual(
            self.tmux("show-options", "-v", "-t", self.a, "@ts_resize_ran"), "1"
        )
        self.assertEqual(self.status(self.b), "needs-input")
        self.tmux("switch-client", "-t", self.b)
        self.wait(lambda: self.status(self.b) == "")

    def test_picker_alignment_colors_and_no_acknowledgement_on_open(self):
        self.configure()
        self.attach()
        self.wait(
            lambda: bool(self.tmux("show-options", "-qv", "-t", self.a, agent.ACK))
        )
        self.state("finished")
        self.state("needs-input", "other-agent", self.other)
        self.helper("picker", self.pane)
        self.assertEqual(
            self.tmux("display-message", "-p", "-t", self.pane, "#{pane_in_mode}"), "1"
        )
        self.assertEqual(self.status(), "finished")
        self.assertEqual(self.status(self.b), "needs-input")
        positions = []
        for session in (self.a, self.b):
            # choose-tree owns the name/colon; -F owns the remainder of the row.
            row = self.tmux(
                "display-message",
                "-p",
                "-t",
                session,
                "#{session_name}: " + agent.SESSION_FORMAT,
            )
            row = re.sub(r"#\[[^]]*\]", "", row)
            positions.append(row.index("●"))
        self.assertEqual(positions[0], positions[1])
        self.tmux("set-option", "-g", "@agent_finished_color", "#123456")
        self.assertIn(
            "#[fg=#123456]●",
            self.tmux("display-message", "-p", "-t", self.a, "#{E:@agent_indicator}"),
        )
        # Reloading the config preserves the user's color choice.
        self.configure()
        self.assertEqual(
            self.tmux("show-options", "-gv", "@agent_finished_color"), "#123456"
        )


if __name__ == "__main__":
    unittest.main()
