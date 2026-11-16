## Delegation policy

- Before spawning ANY subagent, check whether a single Grep/Glob/Read in the main thread answers the question. One tool call beats one agent. A build or test run is one background command, not an agent.
- Route by task to the cheapest agent and model that does the job well. Never default to general-purpose.

| Agent | Use for | Default model | Turn cap |
| --- | --- | --- | --- |
| `scout` | codebase exploration, tracing, fact-finding (read-only) | haiku | 20 |
| `researcher` | web, spec and docs research; notes to .scratch/research/ | sonnet | 30 |
| `validator` | builds, tests, lints, gated checks; logs to .scratch/logs/ | haiku | 25 |
| `implementer` | one scoped change in an isolated git worktree, committed on its own branch | sonnet | 60 |
| `implementer-inplace` | a scoped multi-step change in the current working tree; no worktree, nothing committed | sonnet | 200 |
| `general-purpose` | ONLY when no type above fits. State why first, and put a cap in the brief | inherits | none |

- **Model choice:** haiku for mechanical work (search, run and report). Sonnet for implementation, synthesis and failure triage. Opus only for algorithmically hard or design-heavy work, with the reason in the brief. Override per call with the Agent `model` parameter; do not change a definition for a one-off.
- Maximum 3 subagents in parallel unless I explicitly request a wider fan-out. Prefer sequential when later tasks depend on earlier findings.
- **Brief contract (pre-loaded context).** Every brief carries what the agent needs, so it never rediscovers it:
  - the goal and the decisions that apply
  - what is already known or ruled out, with `path:line` pointers
  - the exact files and sections to read, in order, and nothing broader
  - file ownership, for agents that edit
  - acceptance checks with numbers
  - the handover contract and the status contract (see "Watching subagents").
- **Handover contract.** Every agent hands back a report, never raw context:
  - Agents that edit or run long write a handover file (default `.scratch/handover/<name>.md`) with Result, Evidence (tests, logs, paths), Decisions made, Open items and changes needed from others, and Files changed.
  - The reply to the caller is the result in a few lines plus the handover path. Scouts and short runs reply only, within their line limit.
- **Token efficiency,** for every agent and the lead:
  - Read only what the task needs: Grep or Glob first, then line ranges. Never re-read an unchanged file.
  - Send large output to a file under .scratch/ and read back only the lines needed.
  - Run independent tool calls in parallel in one turn.
  - Run the narrowest test filter that proves a step. Run the full suite once, at the end.
  - Stop as soon as the task is done. No exploring "for completeness".
  - Never restate the brief or paste file contents into a reply.
- Never re-delegate a task an agent already answered; reuse its written notes from .scratch/ instead.

## Watching subagents

Subagents must never run blind for long. I want to know their progress and be able to step in, without tokens spent on polling.

- Every brief for a run expected to take more than about 15 minutes carries a status contract:
  - **Push:** the agent sends one line under 200 characters to the lead with `SendMessage` to "main". It pushes at 2 or 3 named points in the task list, when it finishes or stops, and at once on a blocker or its cap. Otherwise it pushes at most once every 30 minutes. It never waits for a reply.
  - **Progress file:** one `HH:MM task N done - note` line per finished task in `.scratch/logs/<prefix>-progress.md`, and a last line starting `DONE`.
  - **Cap:** an expected tool-call count and a hard stop at about 1.5 times that. At the stop, the agent writes what is done and what is left, then reports. An agent blocked for about 10 tool calls on one problem stops and reports.
- The lead never polls. Each push wakes the lead and costs a turn, so the lead answers with one line at most: no tool calls and no reply to the agent.
- To step in, the lead sends the agent a message with `SendMessage`. It arrives at the agent's next tool call.
- Backstop at no token cost: `~/.claude/scripts/agent-watchdog.sh <name> <progress-file> <stale-min> <cap-min>`, run in the background. It is a shell loop that wakes the lead once, only when the progress file shows DONE, goes stale or passes the time cap. Suggested values: Sonnet 20 min stale and a 90 min cap; Opus 25 min stale and a 120 min cap.
- Prefer agent types with `maxTurns` set, so the harness enforces the cap. Built-in types such as `general-purpose` have no cap, so their brief must carry one.
- When I ask for status, give each agent's state, elapsed time, last push and progress tail from `ListAgents` and the progress file. Never read an agent's transcript file.

## Context hygiene

- Large tool output (test logs, page dumps, long file listings) goes to files under .scratch/ - never into the conversation. Read back only the lines needed.
- When summarising subagent results for me, compress - do not restate their full reports.
- If the session is drifting to a new, unrelated task, tell me to /clear before continuing.
- If context is getting heavy mid-task, suggest `/compact <what to keep>` with a concrete keep-list (e.g. "current diff, failing tests, decisions").
- Do not read whole directories or whole large files when a targeted Grep/line-range Read will do.
- Keep the lead thin: planning, dispatch, merge decisions. Exploration goes through scout.
