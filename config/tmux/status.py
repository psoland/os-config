"""Sample tmux status data outside the server's rendering path."""

import argparse
import contextlib
import fcntl
import hashlib
import math
import os
import re
import subprocess
import time
from pathlib import Path


def cpu_usage(output):
    """Accept only the CPU plugin's numeric percentage, never tmux markup."""
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)%\s*", output)
    if not match:
        raise ValueError("invalid CPU percentage")
    value = float(match[1])
    if not math.isfinite(value) or not 0 <= value <= 100:
        raise ValueError("CPU percentage out of range")
    return value


def save_due(interval, last_save, now):
    # Continuum only sets its timestamp if this server is allowed to autosave.
    # In particular, do not enable autosaving on secondary/test servers.
    try:
        minutes, timestamp = int(interval), int(last_save)
    except ValueError:
        return False
    return minutes > 0 and timestamp > 0 and now >= timestamp + minutes * 60


@contextlib.contextmanager
def locked(socket, server_pid):
    base = (
        Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tmux-status"
    )
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    # A restarted server must not wait for the old worker to notice its exit.
    identity = f"{os.path.realpath(socket)}:{server_pid}"
    name = hashlib.sha256(identity.encode()).hexdigest()
    with (base / f"{name}.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
        else:
            yield True


class Updater:
    def __init__(self, socket, server_pid, cpu_script, continuum_script):
        self.command = ["tmux", "-N", "-S", socket]
        self.server_pid = str(server_pid)
        self.cpu_script = cpu_script
        self.continuum_script = continuum_script
        # Both plugins make their own tmux calls. Pin them to this server too.
        self.env = {**os.environ, "TMUX": f"{socket},{server_pid},0"}
        self.previous = None

    def tmux(self, *args):
        return subprocess.check_output(
            [*self.command, *args],
            env=self.env,
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).rstrip("\n")

    def server_state(self):
        return self.tmux(
            "display-message",
            "-p",
            "#{pid}\t#{@continuum-save-interval}\t#{@continuum-save-last-timestamp}",
        ).split("\t")

    def publish(self, value):
        reading = (
            (f"{value:.1f}", f"{value:5.1f}%") if value is not None else ("0", " --.-%")
        )
        if reading == self.previous:
            return
        # Publish number and display text together, keeping colours in sync.
        self.tmux(
            "set-option",
            "-gq",
            "@status_cpu_usage",
            reading[0],
            ";",
            "set-option",
            "-gq",
            "@status_cpu_text",
            reading[1],
        )
        self.previous = reading

    def tick(self):
        if self.server_state()[0] != self.server_pid:
            return False
        try:
            output = subprocess.check_output(
                [self.cpu_script],
                env=self.env,
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=15,
            )
            value = cpu_usage(output)
        except (OSError, subprocess.SubprocessError, ValueError):
            value = None

        # Sampling may take a second; do not update a replacement server.
        pid, interval, last_save = self.server_state()
        if pid != self.server_pid:
            return False
        self.publish(value)
        if save_due(interval, last_save, time.time()):
            # Retain Continuum's interval, locking and quiet Resurrect save.
            # Its child processes are now forked by this small worker, not tmux.
            with contextlib.suppress(OSError, subprocess.SubprocessError):
                subprocess.run(
                    [self.continuum_script],
                    env=self.env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=30,
                    check=False,
                )
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--server-pid", required=True, type=int)
    parser.add_argument("--cpu-script", required=True)
    parser.add_argument("--continuum-script", required=True)
    parser.add_argument("--interval", type=float, default=10)
    args = parser.parse_args()
    if args.server_pid <= 0 or not math.isfinite(args.interval) or args.interval <= 0:
        parser.error("server PID and interval must be positive")
    with locked(args.socket, args.server_pid) as acquired:
        if not acquired:
            return  # Reloading the config must not start another polling loop.
        updater = Updater(
            args.socket, args.server_pid, args.cpu_script, args.continuum_script
        )
        while True:
            start = time.monotonic()
            try:
                if not updater.tick():
                    return
            except (OSError, subprocess.SubprocessError):
                return  # The server/socket went away; do not start a new server.
            time.sleep(max(0.1, args.interval - (time.monotonic() - start)))


if __name__ == "__main__":
    main()
