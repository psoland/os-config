"""Exercise mobile discovery and shared core terminals in isolated state."""

import argparse
import fcntl
import json
import os
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

# Same probe as the published mobile SSH transport, including its fallback.
MOBILE_CONNECT = (
    "sh -c 'p=$(command -v herdr-core) || { "
    "for d in $HOME/.local/bin /opt/homebrew/bin /usr/local/bin; do "
    "[ -x $d/herdr-core ] && p=$d/herdr-core && break; done; }; "
    '[ -x "$p" ] || { echo "herdr-core is not installed on this machine" >&2; '
    'exit 127; }; exec "$p" connect\''
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", required=True)
    parser.add_argument("--launcher", required=True)
    parser.add_argument("--profile-bin", required=True)
    parser.add_argument("--shell", required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(
        prefix="hc-test-", dir=os.environ.get("TMPDIR")
    ) as temporary:
        root = Path(temporary)
        home = root / "home"
        local_bin = home / ".local/bin"
        local_bin.mkdir(parents=True)
        for name in ["herdr-core", "hc"]:
            (local_bin / name).symlink_to(args.launcher)
        system_bin = root / "system-bin"
        system_bin.mkdir()
        (system_bin / "sh").symlink_to(args.shell)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        # Deliberately no Nix profile or ~/.local/bin in the incoming PATH.
        env = {
            "HOME": str(home),
            "PATH": str(system_bin),
            "SHELL": args.shell,
            "TERM": "xterm-256color",
            "USER": os.environ.get("USER", "nixbld"),
            "HC_SESSION": "dotfiles-test",
            "HC_SOCKET": str(root / "c.sock"),
            "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_DATA_HOME": str(root / "data"),
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_STATE_HOME": str(root / "state"),
            "XDG_RUNTIME_DIR": str(runtime),
            # On macOS choose SSH-mode startup, not a real user's launchd job.
            "SSH_CONNECTION": "127.0.0.1 1234 127.0.0.1 22",
        }

        def call(*arguments, check=True):
            return subprocess.run(
                [args.core, *arguments],
                env=env,
                text=True,
                capture_output=True,
                check=check,
                timeout=20,
            ).stdout

        def mobile(method="hello"):
            request = {"jsonrpc": "2.0", "id": 1, "method": method, "params": {}}
            response = subprocess.run(
                [args.shell, "-c", MOBILE_CONNECT],
                env=env,
                text=True,
                input=json.dumps(request) + "\n",
                capture_output=True,
                check=True,
                timeout=20,
            )
            reply = json.loads(response.stdout.splitlines()[0])
            assert "error" not in reply, reply
            return reply["result"]

        def get():
            data = json.loads(call("get", "shared"))
            return data.get("terminal", data)

        def wait_for(text):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if text in call("read", "shared", "--lines", "40"):
                    return
                time.sleep(0.05)
            raise AssertionError(f"Terminal never printed {text!r}")

        try:
            assert "0.1.21" in subprocess.check_output(
                [str(local_bin / "hc"), "--version"],
                env=env,
                text=True,
            )
            assert isinstance(mobile(), dict)
            status = json.loads(call("server", "status"))
            assert status["installed_by"] == "nix", status
            child_path = call(
                "exec", sys.executable, "-c", "import os; print(os.environ['PATH'])"
            ).strip()
            assert child_path.startswith(args.profile_bin + ":"), child_path

            program = (
                "import sys\n"
                "print('dotfiles-core-ready', flush=True)\n"
                "for count, line in enumerate(sys.stdin, 1):\n"
                " print(f'received:{count}:{line.strip()}', flush=True)\n"
            )
            call(
                "run",
                "--bg",
                "--no-parent",
                "--name",
                "shared",
                "--cwd",
                str(home),
                sys.executable,
                "-u",
                "-c",
                program,
            )
            wait_for("dotfiles-core-ready")
            first = get()
            assert isinstance(first["address"], str), first
            assert first["address"] in {
                t["address"] for t in mobile("terminal.list")["terminals"]
            }
            call("send", "shared", "first")
            wait_for("received:1:first")

            # A terminal viewer can be a normal SSH terminal or a TUI pane.
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
            viewer = subprocess.Popen(
                [args.core, "attach", "shared", "--history", "40"],
                env=env,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                start_new_session=True,
            )
            os.close(slave)
            try:
                screen = b""
                deadline = time.monotonic() + 10
                while (
                    b"dotfiles-core-ready" not in screen and time.monotonic() < deadline
                ):
                    if select.select([master], [], [], 0.1)[0]:
                        screen += os.read(master, 65536)
                assert b"dotfiles-core-ready" in screen, screen
                os.write(master, b"\x1c")  # Ctrl+\ detaches hc attach.
                assert viewer.wait(timeout=10) == 0
            finally:
                if viewer.poll() is None:
                    viewer.terminate()
                    viewer.wait(timeout=10)
                os.close(master)

            assert get()["address"] == first["address"]
            call("send", "shared", "second")
            wait_for("received:2:second")
            assert first["address"] in {
                t["address"] for t in mobile("terminal.list")["terminals"]
            }
            print(
                "PASS: mobile SSH discovery, agent PATH, shared terminal and detach persistence"
            )
        finally:
            call("server", "stop", check=False)


if __name__ == "__main__":
    main()
