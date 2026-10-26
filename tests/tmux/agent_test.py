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

    def view(self, group="", pane=None, source="client"):
        self.helper(
            "view", "--pane", pane or self.pane, "--source", source, "--group", group
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
        # Status worker lifecycle is covered separately; do not start a worker
        # while testing agent events and tmux styles.
        config = "\n".join(
            line for line in config.splitlines() if "${statusHelper}" not in line
        )
        if status_bar:
            for plugin in ("catppuccin",):
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
        self.helper("acknowledge", self.pane)
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
        self.helper("acknowledge", self.pane)
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
        self.helper("acknowledge", self.pane)
        self.assertIn("agents: 1", bar())
        self.assertIn("bg=#a6e3a1]●", bar())

    def test_rendered_session_colour_replaces_catppuccin_cached_green(self):
        installed = Path.home() / ".config/tmux/tmux.conf"
        match = re.search(
            r"run-shell (\S+/catppuccin)/catppuccin\.tmux",
            installed.read_text() if installed.exists() else "",
        )
        if not match or not Path(match[1]).is_dir():
            self.skipTest("an installed Catppuccin plugin is required")
        plugin = Path(match[1])

        def load_theme():
            for name in ("catppuccin_options_tmux.conf", "catppuccin_tmux.conf"):
                self.tmux("source-file", str(plugin / name))

        def segment():
            return self.tmux(
                "display-message", "-p", "-t", self.a, "#{E:@catppuccin_status_session}"
            )

        load_theme()
        self.assertIn("bg=#a6e3a1]", segment())
        for _ in range(2):
            self.configure(status_bar=True)
            load_theme()
            self.assertIn("bg=#b4befe]", segment())
            self.assertNotIn("bg=#a6e3a1]", segment())

    def test_acknowledgement_is_scoped_and_new_events_reappear(self):
        self.state("finished", "one")
        self.state("needs-input", "two", self.other)
        self.helper("acknowledge", self.pane)
        self.assertEqual(self.status(), "")
        self.assertEqual(self.status(self.b), "needs-input")
        self.state("needs-input", "one", self.pane, "--event", "new-request")
        self.assertEqual(self.status(), "needs-input")

    def test_multiple_panes_contribute_and_visit_acknowledges_only_one(self):
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.state("finished", "first")
        self.state("needs-input", "second", split)
        self.assertEqual(self.status(), "needs-input")
        self.helper("acknowledge", self.pane)
        self.assertEqual(self.status(), "needs-input")
        self.assertFalse(self.records()["first"]["unread"])
        self.assertTrue(self.records(split)["second"]["unread"])
        self.helper("acknowledge", split)
        self.assertEqual(self.status(), "")
        self.assertFalse(self.records(split)["second"]["unread"])
        self.assertEqual(self.records(split)["second"]["state"], "needs-input")

    def test_replayed_and_delayed_events_do_not_reassert_attention(self):
        self.state("finished", "one", self.pane, "--event", "done")
        self.helper("acknowledge", self.pane)
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

    def test_actual_hooks_keep_other_windows_and_panes_unread_until_selected(self):
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        window = self.tmux(
            "new-window", "-d", "-t", self.a, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.configure()
        self.state("finished", "active")
        self.state("finished", "split", split)
        self.state("finished", "window", window)
        self.attach()
        self.wait(lambda: not self.records()["active"]["unread"])
        self.assertEqual(self.status(), "finished")
        self.assertTrue(self.records(split)["split"]["unread"])
        self.assertTrue(self.records(window)["window"]["unread"])
        self.tmux("select-pane", "-t", split)
        self.wait(lambda: not self.records(split)["split"]["unread"])
        self.assertEqual(self.status(), "finished")
        # next-window covers navigation beyond explicit select-window commands.
        self.tmux("next-window", "-t", self.a)
        self.wait(lambda: self.status() == "")
        self.assertFalse(self.records(window)["window"]["unread"])

    def test_hidden_window_selection_is_not_a_visit(self):
        self.configure()
        self.attach()
        self.state("finished", "hidden", self.other)
        split = self.tmux(
            "split-window",
            "-d",
            "-t",
            self.other,
            "-P",
            "-F",
            "#{pane_id}",
            "sleep 300",
        )
        self.state("finished", "hidden-split", split)
        self.tmux("select-pane", "-t", split)
        self.helper("acknowledge", "--if-visible", split)
        self.assertTrue(self.records(split)["hidden-split"]["unread"])
        self.tmux("switch-client", "-t", self.b)
        self.wait(lambda: not self.records(split)["hidden-split"]["unread"])
        self.assertTrue(self.records(self.other)["hidden"]["unread"])
        self.assertEqual(self.status(self.b), "finished")

    def test_conversation_view_and_pane_visits_acknowledge_only_displayed_group(self):
        self.configure()
        self.attach(self.b)
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.state("finished", "second", self.pane, "--group", "client:second")
        self.view("client:first")
        self.assertTrue(self.records()["first"]["unread"])
        self.tmux("switch-client", "-t", self.a)
        self.wait(lambda: not self.records()["first"]["unread"])
        self.assertTrue(self.records()["second"]["unread"])
        self.assertEqual(self.status(), "finished")
        self.view("client:second")
        self.assertEqual(self.status(), "")
        self.assertFalse(self.records()["second"]["unread"])
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.helper("acknowledge", self.pane)
        self.assertEqual(self.status(), "finished")
        # Leaving the conversation for OpenCode's home screen displays none.
        self.view()
        self.helper("acknowledge", self.pane)
        self.assertTrue(self.records()["first"]["unread"])

    def test_detached_conversation_view_does_not_acknowledge(self):
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.view("client:first")
        self.assertTrue(self.records()["first"]["unread"])
        self.helper("acknowledge", "--if-visible", self.pane)
        self.assertTrue(self.records()["first"]["unread"])

    def test_current_conversation_notifications_are_read_without_navigation(self):
        self.attach()
        self.view("client:first")
        self.state("finished", "background", self.pane, "--group", "client:second")
        self.state("running", "current", self.pane, "--group", "client:first")
        self.state("finished", "current", self.pane, "--group", "client:first")
        self.assertFalse(self.records()["current"]["unread"])
        self.assertTrue(self.records()["background"]["unread"])
        self.assertEqual(self.status(), "finished")
        self.view("client:second")
        self.assertEqual(self.status(), "")
        self.state("needs-input", "prompt", self.pane, "--group", "client:second")
        self.assertFalse(self.records()["prompt"]["unread"])
        self.assertEqual(self.status(), "")

    def test_displayed_conversation_finishing_in_hidden_panes_stays_unread(self):
        split = self.tmux(
            "split-window", "-d", "-t", self.pane, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        window = self.tmux(
            "new-window", "-d", "-t", self.a, "-P", "-F", "#{pane_id}", "sleep 300"
        )
        self.attach()
        for pane in (split, window, self.other):
            with self.subTest(pane=pane):
                self.view("client:first", pane)
                self.state("finished", "hidden", pane, "--group", "client:first")
                self.assertTrue(self.records(pane)["hidden"]["unread"])

    def test_displayed_conversation_finishing_while_detached_stays_unread(self):
        self.view("client:first")
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.assertTrue(self.records()["first"]["unread"])

    def test_displayed_conversation_finishing_under_picker_stays_unread(self):
        self.attach()
        self.view("client:first")
        self.helper("picker", self.pane)
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.assertTrue(self.records()["first"]["unread"])

    def test_conversation_view_does_not_acknowledge_picker_previews(self):
        self.configure()
        self.attach()
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.helper("picker", self.pane)
        self.view("client:first")
        self.helper("acknowledge", "--if-visible", self.pane)
        self.assertTrue(self.records()["first"]["unread"])

    def test_group_acknowledgement_is_scoped_and_preserves_newer_events(self):
        self.state(
            "finished", "first", self.pane, "--group", "client:first", "--at", "100"
        )
        self.state(
            "finished", "second", self.pane, "--group", "client:second", "--at", "100"
        )
        tracker = agent.Tracker(self.socket)
        # Direct calls let us control the event/visit order without wall-clock races.
        tracker.acknowledge(self.pane, 150, "client:first")
        self.assertFalse(self.records()["first"]["unread"])
        self.assertTrue(self.records()["second"]["unread"])
        self.state(
            "needs-input", "late", self.pane, "--group", "client:first", "--at", "120"
        )
        self.assertFalse(self.records()["late"]["unread"])
        self.state(
            "finished", "first", self.pane, "--group", "client:first", "--at", "200"
        )
        tracker.acknowledge(self.pane, 175, "client:first")
        self.assertTrue(self.records()["first"]["unread"])
        # Reading one pane must not suppress delayed events in a different pane.
        self.state(
            "finished", "other", self.other, "--group", "client:first", "--at", "120"
        )
        self.assertTrue(self.records(self.other)["other"]["unread"])

    def test_moving_window_preserves_conversation_view_and_acknowledgement(self):
        self.state(
            "finished", "read", self.pane, "--group", "client:first", "--at", "100"
        )
        self.state(
            "finished", "unread", self.pane, "--group", "client:second", "--at", "100"
        )
        self.view("client:first")
        agent.Tracker(self.socket).acknowledge(self.pane, 150, "client:first")
        self.tmux("move-window", "-s", f"{self.a}:0", "-t", self.b)
        self.helper("acknowledge", self.pane)
        self.assertFalse(self.records()["read"]["unread"])
        self.assertTrue(self.records()["unread"]["unread"])
        self.assertEqual(self.status(self.b), "finished")

    def test_visiting_copy_mode_pane_counts_as_reading(self):
        self.configure()
        self.attach(self.b)
        self.state("finished", "first", self.pane, "--group", "client:first")
        self.view("client:first")
        self.tmux("copy-mode", "-t", self.pane)
        self.tmux("switch-client", "-t", self.a)
        self.wait(lambda: self.status() == "")
        self.assertFalse(self.records()["first"]["unread"])

    def test_picker_alignment_colors_and_no_acknowledgement_on_open(self):
        self.configure()
        self.attach()
        self.wait(
            lambda: bool(self.tmux("show-options", "-pqv", "-t", self.pane, agent.ACK))
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
