---
name: agent-routing
description: Choose subagents for orchestration, research, implementation, or simple execution.
---

# Agent routing

Use the lightest agent that can reliably finish the task. Follow the live
subagent catalog if it differs from these defaults.

| Agent | Use for |
| --- | --- |
| `astra` | Most capable: orchestration, ambiguous goals, architecture, difficult reasoning, and conflicting evidence. Delegate routine execution. |
| `sol` | Research, debugging, and development requiring discovery, synthesis, or implementation decisions. |
| `luna-worker` | Low-cost execution: precise, easily verified tasks such as mechanical edits, bounded lookups, specified checks, and authorized commits. |
| `explore` | Read-only code discovery: locate files, trace behavior, and identify conventions. Specify quick, medium, or very thorough. |
| `general` | Self-contained, multi-step investigations across sources or tools. |

`luna` is primary-only, not a subagent. `explore` and `general` inherit the
parent's model unless configured otherwise; do not assume they are cheaper.

## Delegation

- Give each worker the objective, necessary context, scope, and acceptance checks.
- Parallelize independent tasks only; avoid overlapping file edits.
- Escalate unexpected complexity from `luna-worker` to `sol`, then to `astra`
  when needed. Route difficult or high-risk work directly to a stronger agent.
- Verify results, preserve authorization boundaries, and request concise reports.
  Handle tiny tasks directly when delegation adds more overhead than value.
