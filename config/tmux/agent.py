"""Event-driven agent indicators for tmux. State lives in pane options, not files."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

RECORDS = "@agent_records"
STATUS = "@agent_status"
RUNNING_COUNT = "@agent_running_count"
ACK = "@agent_ack"
STATES = ("running", "finished", "needs-input", "idle")
SESSION_FORMAT = (
    "#{R: ,#{e|-:#{@agent_name_width},#{w:session_name}}}"
    "#{E:@agent_indicator}#{session_windows} windows"
    "#{?session_grouped, (group #{session_group}: #{session_group_list}),}"
    "#{?session_attached, (attached),}"
)
TREE_FORMAT = (
    "#{?pane_format,"
    "#{?pane_marked,#[reverse],}#{pane_current_command}#{pane_flags}"
    '#{?#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}},: "#{pane_title}",},'
    "#{?window_format,"
    "#{?window_marked_flag,#[reverse],}#{window_name}#{window_flags},"
    + SESSION_FORMAT
    + "}}"
)


def aggregate(records):
    records = list(records)
    for state in ("needs-input", "finished"):
        if any(record["state"] == state and record["unread"] for record in records):
            return state
    return "running" if any(record["state"] == "running" for record in records) else ""


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


class Tracker:
    def __init__(self, socket):
        self.command = ["tmux", "-S", socket]
        self.socket = socket

    def tmux(self, *args):
        return subprocess.check_output(
            [*self.command, *args], text=True, stderr=subprocess.DEVNULL, timeout=10
        ).rstrip("\n")

    @contextlib.contextmanager
    def locked(self):
        # Serialize read/modify/write across clients and tmux hooks. Only a lock
        # file is stored on disk; a crashed helper releases the OS lock.
        base = (
            Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
            / "tmux-agent"
        )
        base.mkdir(mode=0o700, parents=True, exist_ok=True)
        identity = hashlib.sha256(os.path.realpath(self.socket).encode()).hexdigest()
        with (base / f"{identity}.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def panes(self):
        rows = self.tmux(
            "list-panes", "-a", "-F", f"#{{session_id}}\t#{{pane_id}}\t#{{{RECORDS}}}"
        )
        result = []
        for row in rows.splitlines():
            session, pane, raw = row.split("\t", 2)
            try:
                records = json.loads(raw) if raw else {}
                if not isinstance(records, dict):
                    records = {}
            except json.JSONDecodeError:
                records = {}
            result.append((session, pane, records))
        return result

    def save(self, pane, records):
        self.tmux(
            "set-option",
            "-p",
            "-t",
            pane,
            RECORDS,
            json.dumps(records, separators=(",", ":")),
        )

    def refresh(self):
        sessions = {
            row: []
            for row in self.tmux("list-sessions", "-F", "#{session_id}").splitlines()
        }
        for session, pane, records in self.panes():
            live = {
                key: value
                for key, value in records.items()
                if not value.get("pid") or alive(value["pid"])
            }
            if live != records:
                self.save(pane, live)
            sessions[session].extend(live.values())
        commands = []
        for session, records in sessions.items():
            options = {
                STATUS: aggregate(records),
                RUNNING_COUNT: str(sum(record["state"] == "running" for record in records)),
            }
            for option, value in options.items():
                if commands:
                    commands.append(";")
                commands.extend(["set-option", "-t", session, option, value])
        if commands:
            self.tmux(*commands)

    def state(self, pane, source, state, event, at, pid):
        rows = [
            (session, records)
            for session, target, records in self.panes()
            if target == pane
        ]
        if not rows:
            return  # The agent's pane may have closed before its final event.
        session, records = rows[0]
        previous = records.get(source)
        # Replayed/duplicated events must not light up an acknowledged dot.
        if previous and (
            at < previous["at"] or (event and event == previous.get("event"))
        ):
            return
        ack = self.tmux("show-options", "-qv", "-t", session, ACK)
        records[source] = {
            "state": state,
            "event": event,
            "at": at,
            "pid": pid,
            "unread": state in ("finished", "needs-input") and at > float(ack or 0),
        }
        self.save(pane, records)
        self.refresh()

    def acknowledge(self, session, at):
        previous = self.tmux("show-options", "-qv", "-t", session, ACK)
        at = max(at, float(previous or 0))
        self.tmux("set-option", "-t", session, ACK, str(at))
        seen = set()
        for target, pane, records in self.panes():
            if target != session or pane in seen:
                continue
            seen.add(pane)
            for record in records.values():
                if record["at"] <= at:
                    record["unread"] = False
            self.save(pane, records)
        self.refresh()

    def remove(self, pane, source):
        for _, target, records in self.panes():
            if target == pane:
                records.pop(source, None)
                self.save(pane, records)
                break
        self.refresh()

    def picker(self, pane):
        self.refresh()
        widths = self.tmux("list-sessions", "-F", "#{w:session_name}").splitlines()
        self.tmux(
            "set-option",
            "-g",
            "@agent_name_width",
            str(max(map(int, widths), default=0)),
        )
        self.tmux("choose-tree", "-t", pane, "-Zs", "-O", "name", "-F", TREE_FORMAT)


def main():
    parser = argparse.ArgumentParser(prog="tmux-agent", description=__doc__)
    socket = os.environ.get("TMUX", "").rsplit(",", 2)[0]
    parser.add_argument("--socket", default=socket)
    commands = parser.add_subparsers(dest="command", required=True)
    state = commands.add_parser("state", help="report one agent's state")
    state.add_argument("state", choices=STATES)
    state.add_argument("--pane", default=os.environ.get("TMUX_PANE"), required=False)
    state.add_argument("--source", required=True)
    state.add_argument("--event", default="")
    state.add_argument(
        "--at", type=float, default=None, help="event time in Unix milliseconds"
    )
    state.add_argument(
        "--pid",
        type=int,
        default=None,
        help="local agent process, for stale-state cleanup",
    )
    ack = commands.add_parser(
        "acknowledge", help="acknowledge a session's existing notifications"
    )
    ack.add_argument("session")
    remove = commands.add_parser("remove", help="unregister one agent")
    remove.add_argument("--pane", default=os.environ.get("TMUX_PANE"))
    remove.add_argument("--source", required=True)
    picker = commands.add_parser(
        "picker", help="open the native picker with aligned indicators"
    )
    picker.add_argument("pane")
    commands.add_parser(
        "refresh", help="drop dead clients and recalculate session indicators"
    )
    args = parser.parse_args()
    if not args.socket:
        parser.error("run inside tmux or supply --socket")
    if args.command in ("state", "remove"):
        if not args.pane or not re.fullmatch(r"%\d+", args.pane):
            parser.error("a valid tmux pane ID is required")
        if len(args.source) > 200 or not args.source:
            parser.error("source must contain 1–200 characters")
    if args.command == "state" and args.pid is not None and args.pid <= 0:
        parser.error("pid must be positive")
    # Capture time before waiting for the lock so a delayed acknowledgement
    # cannot accidentally erase an event that occurred after it started.
    at = time.time() * 1000
    tracker = Tracker(args.socket)
    try:
        with tracker.locked():
            if args.command == "state":
                tracker.state(
                    args.pane,
                    args.source,
                    args.state,
                    args.event,
                    args.at if args.at is not None else at,
                    args.pid,
                )
            elif args.command == "acknowledge":
                tracker.acknowledge(args.session, at)
            elif args.command == "remove":
                tracker.remove(args.pane, args.source)
            elif args.command == "picker":
                tracker.picker(args.pane)
            else:
                tracker.refresh()
    except (subprocess.SubprocessError, OSError, ValueError) as error:
        parser.exit(1, f"tmux-agent: {error}\n")


if __name__ == "__main__":
    main()
