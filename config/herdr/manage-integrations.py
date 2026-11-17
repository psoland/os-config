"""Adopt Herdr assets and merge only the dotfiles-owned hook registrations."""

import argparse
import copy
import datetime
import json
import os
import shlex
import shutil
import tempfile
from pathlib import Path

import tomlkit


class Manager:
    def __init__(self, home, config_home, state_home):
        self.home = Path(home)
        self.config_home = Path(config_home)
        stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S.%f")
        self.backups = Path(state_home) / "herdr/dotfiles-backups" / stamp

    def backup(self, path):
        # Numbered paths also handle config directories outside HOME.
        self.backups.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = self.backups / f"{len(list(self.backups.iterdir())):02d}-{path.name}"
        shutil.copy2(path, target)
        target.chmod(0o600)
        print(f"Herdr: backed up {path} to {target}")

    def write(self, path, content):
        if path.exists() and path.read_text() == content:
            return
        # Do not follow an externally managed config symlink when writing.
        if path.is_symlink():
            raise ValueError(f"Refusing to replace managed config symlink: {path}")
        if path.exists():
            self.backup(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as handle:
                handle.write(content)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def adopt(self):
        files = [
            (self.config_home / "herdr/config.toml", None),
            (self.home / ".pi/agent/extensions/herdr-agent-state.ts", "pi"),
            (self.home / ".claude/hooks/herdr-agent-state.sh", "claude"),
            (self.home / ".codex/herdr-agent-state.sh", "codex"),
            (self.config_home / "opencode/plugins/herdr-agent-state.js", "opencode"),
        ]
        # Validate every asset before making changes.
        for path, agent in files:
            if path.is_symlink():
                if not path.resolve().is_relative_to("/nix/store"):
                    raise ValueError(f"Refusing to adopt unmanaged symlink: {path}")
                continue
            if not path.exists():
                continue
            if agent and f"HERDR_INTEGRATION_ID={agent}" not in path.read_text():
                raise ValueError(f"Refusing to adopt unrecognized integration: {path}")
        for path, _ in files:
            if path.is_symlink() or not path.exists():
                continue
            self.backup(path)
            path.unlink()

    def configure(self, declarations):
        for agent, relative, script in [
            ("claude", ".claude/settings.json", ".claude/hooks/herdr-agent-state.sh"),
            ("codex", ".codex/hooks.json", ".codex/herdr-agent-state.sh"),
        ]:
            path = self.home / relative
            original = json.loads(path.read_text()) if path.exists() else {}
            updated = merge_hooks(original, declarations[agent], self.home / script)
            if original != updated:
                self.write(path, json.dumps(updated, indent=2) + "\n")

        path = self.home / ".codex/config.toml"
        content = path.read_text() if path.exists() else ""
        document = tomlkit.parse(content)
        features = document.setdefault("features", tomlkit.table())
        if features.get("hooks") is not True:
            features["hooks"] = True
            self.write(path, tomlkit.dumps(document))


def merge_hooks(original, declaration, script):
    result = copy.deepcopy(original)
    hooks = result.setdefault("hooks", {})
    # Remove obsolete Herdr registrations from all events, retaining user hooks
    # even when they share a matcher block with Herdr's command.
    for event, groups in list(hooks.items()):
        kept = []
        for group in groups:
            entries = group.get("hooks", [])
            remaining = [
                entry
                for entry in entries
                if not is_herdr_command(entry.get("command", ""))
            ]
            if remaining == entries:
                kept.append(group)
            elif remaining:
                kept.append({**group, "hooks": remaining})
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    additions = copy.deepcopy(declaration)
    for event, groups in additions.items():
        for group in groups:
            for entry in group["hooks"]:
                entry["command"] = entry["command"].replace(
                    "{script}", shlex.quote(str(script))
                )
        hooks.setdefault(event, []).extend(groups)
    return result


def is_herdr_command(command):
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    if not words:
        return False
    if Path(words[0]).name in {"bash", "sh"}:
        words = words[1:]
    return bool(words) and Path(words[0]).name == "herdr-agent-state.sh"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", required=True)
    parser.add_argument("--config-home", required=True)
    parser.add_argument("--state-home", required=True)
    parser.add_argument("--declarations", type=Path, required=True)
    parser.add_argument("operation", choices=["adopt", "configure"])
    args = parser.parse_args()
    manager = Manager(args.home, args.config_home, args.state_home)
    if args.operation == "adopt":
        manager.adopt()
    else:
        manager.configure(json.loads(args.declarations.read_text()))


if __name__ == "__main__":
    main()
