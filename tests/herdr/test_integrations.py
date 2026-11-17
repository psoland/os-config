import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import tomlkit

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "manage_integrations", ROOT / "config/herdr/manage-integrations.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
DECLARATIONS = json.loads((ROOT / "config/herdr/agent-hooks.json").read_text())


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "home with spaces"
        self.home.mkdir()
        self.manager = MODULE.Manager(
            self.home, self.home / ".config", self.home / ".local/state"
        )

    def write(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_preserves_unrelated_settings_and_hooks_and_is_idempotent(self):
        original = {
            "theme": "dark",
            "skipWorkflowUsageWarning": True,
            "hooks": {
                "SessionStart": [
                    {
                        "matcher": "custom",
                        "hooks": [
                            {"type": "command", "command": "echo herdr-agent-state.sh"},
                            {
                                "type": "command",
                                "command": "bash /old/herdr-agent-state.sh idle",
                            },
                        ],
                    }
                ],
                "Stop": [{"hooks": [{"command": "echo keep"}]}],
            },
        }
        path = self.write(".claude/settings.json", json.dumps(original))
        codex = self.write(
            ".codex/config.toml",
            '# keep this comment\nmodel = "local"\n[features]\nhooks = false\njs_repl = false\n',
        )
        self.manager.configure(DECLARATIONS)
        updated = json.loads(path.read_text())
        self.assertEqual(updated["theme"], "dark")
        self.assertTrue(updated["skipWorkflowUsageWarning"])
        self.assertEqual(updated["hooks"]["Stop"], original["hooks"]["Stop"])
        self.assertEqual(
            updated["hooks"]["SessionStart"][0]["hooks"],
            [{"type": "command", "command": "echo herdr-agent-state.sh"}],
        )
        command = updated["hooks"]["SessionStart"][-1]["hooks"][0]["command"]
        self.assertIn(f"'{self.home}/.claude/hooks/herdr-agent-state.sh'", command)
        document = tomlkit.parse(codex.read_text())
        self.assertTrue(document["features"]["hooks"])
        self.assertFalse(document["features"]["js_repl"])
        self.assertEqual(document["model"], "local")
        self.assertIn("# keep this comment", codex.read_text())
        backups = sorted(self.manager.backups.iterdir())
        before = (path.read_text(), codex.read_text(), path.stat().st_mtime_ns)
        self.manager.configure(DECLARATIONS)
        self.assertEqual(
            (path.read_text(), codex.read_text(), path.stat().st_mtime_ns), before
        )
        self.assertEqual(sorted(self.manager.backups.iterdir()), backups)
        self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in backups))

    def test_fresh_install_creates_both_registrations_and_codex_feature(self):
        self.manager.configure(DECLARATIONS)
        for relative in [".claude/settings.json", ".codex/hooks.json"]:
            path = self.home / relative
            self.assertEqual(
                len(json.loads(path.read_text())["hooks"]["SessionStart"]), 1
            )
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(
            tomlkit.parse((self.home / ".codex/config.toml").read_text())["features"][
                "hooks"
            ]
        )

    def test_adopts_only_known_assets_and_preserves_managed_symlinks(self):
        paths = [
            self.write(".config/herdr/config.toml", "onboarding = false\n"),
            self.write(
                ".pi/agent/extensions/herdr-agent-state.ts",
                "// HERDR_INTEGRATION_ID=pi\n",
            ),
            self.write(
                ".config/opencode/plugins/herdr-agent-state.js",
                "// HERDR_INTEGRATION_ID=opencode\n",
            ),
        ]
        managed = self.home / ".codex/herdr-agent-state.sh"
        managed.parent.mkdir()
        managed.symlink_to("/nix/store/herdr-test-managed-script")
        self.manager.adopt()
        self.assertTrue(all(not path.exists() for path in paths))
        self.assertTrue(managed.is_symlink())
        self.assertEqual(len(list(self.manager.backups.iterdir())), 3)
        self.manager.adopt()
        self.assertEqual(len(list(self.manager.backups.iterdir())), 3)

    def test_unrecognized_asset_aborts_before_any_adoption(self):
        config = self.write(".config/herdr/config.toml", "onboarding = false\n")
        unknown = self.write(
            ".pi/agent/extensions/herdr-agent-state.ts", "// user implementation\n"
        )
        with self.assertRaisesRegex(ValueError, "unrecognized integration"):
            self.manager.adopt()
        self.assertTrue(config.exists())
        self.assertTrue(unknown.exists())
        self.assertFalse(self.manager.backups.exists())

    def test_managed_agent_configs_are_not_overwritten(self):
        source = self.write("settings.json", "{}")
        path = self.home / ".claude/settings.json"
        path.parent.mkdir()
        path.symlink_to(source)
        with self.assertRaisesRegex(ValueError, "config symlink"):
            self.manager.configure(DECLARATIONS)
        self.assertEqual(source.read_text(), "{}")

    def test_unmanaged_asset_symlink_aborts_adoption(self):
        source = self.write("user.ts", "// user work\n")
        link = self.home / ".pi/agent/extensions/herdr-agent-state.ts"
        link.parent.mkdir(parents=True)
        link.symlink_to(source)
        with self.assertRaisesRegex(ValueError, "unmanaged symlink"):
            self.manager.adopt()
        self.assertTrue(link.is_symlink())
        self.assertEqual(source.read_text(), "// user work\n")


if __name__ == "__main__":
    unittest.main()
