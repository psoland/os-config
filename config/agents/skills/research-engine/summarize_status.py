"""Reads a research_status JSON-RPC response on stdin.

Exit 0 and print one line per run when every expected run is terminal; exit 1 otherwise
(still running, or the response was not usable). `--force` prints whatever is there.
"""
import json
import sys

TERMINAL = {"completed", "partial", "failed"}
expected = int(sys.argv[1])
force = "--force" in sys.argv

try:
    runs = json.loads(sys.stdin.read())["result"]["structuredContent"]["runs"]
except Exception:
    sys.exit(1)

done = len(runs) == expected and all(r["state"] in TERMINAL for r in runs)
if not (done or force):
    sys.exit(1)

for r in runs:
    sq = r["sub_questions"]
    print("%s  %-9s %-20s claims=%-3s recalled=%s/%s  %s" % (
        r["run_id"], r["state"], r.get("ended_reason") or "-", r["findings"],
        sq["recalled"], sq["total"], r["question"][:80]))
print("ALL RESEARCH FINISHED -> call get_knowledge for each run_id" if done else "NOT FINISHED")
