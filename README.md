# Token Diet for Claude Code

A set of Claude Code subagents, a CLAUDE.md delegation policy and a local usage report. The goal is lower token use. The main session stays small, and searching, research, test runs and scoped edits go to capped agents on cheaper models.

## Why

In long Claude Code sessions most tokens are cache reads. A cache read is the earlier conversation being sent to the model again on every turn. A session that has read many files carries all of them through every later turn.

Cost is roughly context size times turns times model price. This pack works on all three:

- Exploration, web research and builds run in subagents. A subagent is a separate Claude instance with its own context. Only its short report comes back to the main session, which these files call the "lead".
- Each agent runs on Haiku or Sonnet and has a turn cap.
- The CLAUDE.md snippet tells the lead when to delegate, how to brief an agent and how to keep its own context small.

## What is in this repo

```
agents/
  scout.md                 read-only code search (Haiku)
  researcher.md            web and docs research (Sonnet)
  validator.md             builds, tests and lints (Haiku)
  implementer.md           one change in its own git worktree (Sonnet)
  implementer-inplace.md   a multi-step change in the current working tree (Sonnet)
CLAUDE-md-snippet.md       delegation policy to add to your CLAUDE.md
settings.example.json      env setting for the default subagent model
tools/
  install.cmd              double-click wrapper for install.ps1
  install.ps1              Windows installer and uninstaller
  analyze_usage_v3.py      local token usage report
  PLAYBOOK.md              which mode to use for which task, with prompt templates
```

## The agents

| Agent | Model | Turn cap | Tools | Use it for |
|---|---|---|---|---|
| `scout` | haiku | 20 | Glob, Grep, Read | Finding files, tracing symbols, answering "where or how is X done". Never edits or runs commands. |
| `researcher` | sonnet | 30 | WebSearch, WebFetch, Read, Write, Glob, SendMessage, ToolSearch | Specs, API docs, release notes and changelogs. Writes notes to `.scratch/research/`. |
| `validator` | haiku | 25 | Bash, Read, Grep, Glob, SendMessage, ToolSearch | Builds, tests, linters and other gates. Reports pass or fail and fixes nothing. |
| `implementer` | sonnet | 60 | Read, Edit, Write, Bash, Grep, Glob, SendMessage, ToolSearch | One scoped code change in an isolated git worktree, committed on its own branch. |
| `implementer-inplace` | sonnet | 200 | Same as `implementer` | A scoped multi-step change in your working tree. No worktree and no commits. |

The turn cap is `maxTurns` in each agent's frontmatter. Claude Code stops the agent when it reaches the cap. Each agent is also told to stop a few turns earlier and write its report with what it has.

### scout

Read-only investigation. It searches with Grep and Glob, then reads only the line ranges it needs. If about 8 tool calls find nothing, it reports what it searched and stops. Its reply is at most 25 lines of `path:line - fact` bullets, ending with a 1 to 3 sentence answer.

### researcher

It checks `.scratch/research/` for earlier notes first. Then it runs 1 to 6 searches and fetches only the pages that matter, preferring official docs, specs and repos. Full notes with source URLs and dates go to the path you give, or `.scratch/research/<topic>.md`. Its reply is at most 15 lines with findings, sources and confidence.

### validator

It runs the commands you give, or the ones documented in the project's README or CLAUDE.md. Full output goes to `.scratch/logs/<name>.log`. The reply has one `PASS|FAIL - command - exit code - duration` line per command, plus the few error lines that matter. It runs on Haiku by default. Ask for Sonnet when failures need diagnosis.

### implementer

It uses `isolation: worktree`. Claude Code gives the agent its own git worktree, which is a second checkout of the repo on a separate branch. Parallel implementers therefore cannot overwrite each other's edits. This needs a git repo with at least one commit.

It edits only the files the brief assigns to it, builds, runs the relevant tests and commits on its branch. It never merges, rebases or pushes. Its reply is at most 20 lines: branch, files changed and PASS or FAIL.

### implementer-inplace

For repos with uncommitted work, or where you do not want agents to commit. It works in your current tree, which other agents may share, so it edits only the files it owns. It never commits, pushes, stashes, resets or checks out.

It writes a handover file to `.scratch/handover/<name>.md` and one line per finished task to `.scratch/logs/<name>-progress.md`. Its reply is at most 30 lines.

## Using the agents

Claude Code picks a subagent by matching your request to the agent's `description`. These descriptions say "Use PROACTIVELY", so the lead tends to use them without being asked. You can also name one:

```
Use the scout agent to find where the HTTP retry policy is configured.
Use the researcher agent: what changed in the Node.js fetch API between Node 20 and 22? Notes to .scratch/research/node-fetch.md.
Use the validator agent to run the unit tests filtered to "Parser" and report pass or fail.
```

Run `/agents` in Claude Code to see the installed agents.

**Brief the agent fully.** The agents start from the brief and are told not to rediscover what it states. A good brief carries:

- the goal and the decisions that apply
- what is already known or ruled out, with `path:line` pointers
- the exact files to read, in order
- the files the agent owns, for implementers
- acceptance checks with numbers
- where to write the handover file

**Pick the right implementer.** Use `implementer` for independent changes that can each live on their own branch. Use `implementer-inplace` when work must stay in the current tree, or when commits are not allowed. Give parallel agents separate files. Two tasks that share a file are one task.

**Status on long runs.** The researcher, validator and both implementers can send one-line status updates to the lead with `SendMessage`, addressed to "main". If that tool is not loaded yet, they load it with `ToolSearch`. Implementers also write a progress file. To change an agent's course, ask the lead to send it a message. The message arrives at the agent's next tool call.

**Change the model for one run.** Ask the lead to run an agent on a different model, for example "run the validator on sonnet". A model given on a single call takes precedence over the agent's frontmatter.

**Project agents.** You can also put these files in a repo's `.claude/agents/` folder to share them with a team through git.

## The CLAUDE.md snippet

`CLAUDE-md-snippet.md` holds three sections for your user-level `CLAUDE.md` (`%USERPROFILE%\.claude\CLAUDE.md` on Windows, `~/.claude/CLAUDE.md` elsewhere):

- **Delegation policy.** Try a single Grep, Glob or Read before spawning an agent. Route each task to the cheapest agent and model that does it well. Run at most 3 agents in parallel. It also sets the brief and handover rules and the token-saving rules.
- **Watching subagents.** Runs expected to take over about 15 minutes get status pushes, a progress file and a tool-call cap. The lead never polls.
- **Context hygiene.** Large output goes to files under `.scratch/`. Agent reports get compressed. Use `/clear` or `/compact` when a session drifts or gets heavy.

The snippet is written in the first person, as instructions from you to Claude. Edit it to suit you.

One bullet in "Watching subagents" mentions `~/.claude/scripts/agent-watchdog.sh`. That script is not in this repo. Remove the bullet or supply your own script.

## Settings

`settings.example.json`:

```json
{
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet"
  }
}
```

`CLAUDE_CODE_SUBAGENT_MODEL` sets the model for subagents whose definition names none, such as the built-in `general-purpose` agent. Without it, those agents use the lead's model, which may be Opus. The agents in this repo set their own model, so this is a backstop. A model given on a single agent call overrides both.

## Tools

### install.cmd and install.ps1 (Windows)

The installer reads everything from this repo, from the folder above `tools`. It does not download anything or copy from anywhere else. It stops with an error if run from a copy inside `%USERPROFILE%\.claude`.

Run it from any folder, or double-click `install.cmd`:

```
tools\install.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
```

`install.cmd` passes its arguments through to `install.ps1` and pauses at the end so you can read the output.

It changes these files, all under `%USERPROFILE%\.claude`:

| From the repo | To | Notes |
|---|---|---|
| `agents\*.md` | `agents\` | Every agent file. Replaces files with the same name and leaves other agents alone. |
| `CLAUDE-md-snippet.md` | appended to `CLAUDE.md` | Once. Skipped if `CLAUDE.md` already has a `## Delegation policy` heading. |
| `settings.example.json` | `env` keys merged into `settings.json` | Writes `settings.json.bak-<timestamp>` first. All other settings are kept. |
| `tools\analyze_usage_v3.py`, `tools\PLAYBOOK.md` | `tools\` | |

Options:

| Option | Effect |
|---|---|
| `-SubagentModel sonnet` or `haiku` | Use this value for `CLAUDE_CODE_SUBAGENT_MODEL` instead of the one in `settings.example.json`. |
| `-SubagentModel none` | Leave `settings.json` untouched. |
| `-NoClaudeMd` | Leave `CLAUDE.md` untouched. |
| `-Uninstall` | Remove what the install added. |

Example: `tools\install.cmd -SubagentModel haiku -NoClaudeMd`

After installing, restart Claude Code or VS Code. A new agents folder needs one restart, and env changes need a new session. Then run `/agents` to check that the five agents are listed.

Running the installer again updates the agents, tools and env keys. It does not update CLAUDE.md once the section is there. Edit that by hand.

`tools\install.cmd -Uninstall` removes:

- agent files with the same names as the ones in this repo's `agents\`
- the snippet sections in `CLAUDE.md`, from `## Delegation policy` to the next heading that is not part of the snippet
- the env keys listed in `settings.example.json`, after writing a backup
- the two tools files

Uninstall removes those CLAUDE.md sections even if you wrote or edited them yourself. Add `-NoClaudeMd` to keep them, or `-SubagentModel none` to keep `settings.json` as it is.

Windows PowerShell 5.1, which `install.cmd` uses, rewrites `settings.json` with wide indentation and escapes such as `'`. The settings are unchanged. For readable output, run `install.ps1` with PowerShell 7 (`pwsh`) instead.

### analyze_usage_v3.py

This script reads the session transcripts Claude Code keeps on your machine (`~/.claude/projects/**/*.jsonl`) and prints a token usage report. It uses only the Python standard library and sends nothing anywhere.

```
py tools\analyze_usage_v3.py --days 7
python3 tools/analyze_usage_v3.py --days 30 --top 10
```

After installing, it is also at `%USERPROFILE%\.claude\tools\analyze_usage_v3.py`.

| Option | Default | Meaning |
|---|---|---|
| `--days` | 30 | Count only records from the last N days. |
| `--root` | `~/.claude/projects` | Folder to scan. |
| `--top` | 10 | How many sessions to list. Projects list at least 10. |

The report has these sections:

- **Grand total** and the share of it that is cache reads.
- **Tokens by model.** `in` is input, `out` is output, `cw` is cache writes and `cr` is cache reads.
- **Main thread vs subagents.**
- **By project.** Total, subagent share, sessions and agent transcript files.
- **Sessions.** How many, and how many spanned 8 hours or more.
- **Top sessions.** Total, wall-clock hours, subagent share and average context. Average context is cache-read tokens divided by assistant turns. It estimates how much context each turn replayed.

Claude Code writes one transcript line per streamed block of a reply, and each line repeats the same usage numbers. The script counts each API call once, keyed on message id and request id. Subagent transcripts in `subagents/` folders count towards their parent session when the ids match.

Each week, watch three numbers: the Haiku plus Sonnet share of tokens, the average context of your top sessions, and how much of the total a few sessions take.

Project names in the report are Claude Code's folder names, which are built from your local repo paths. Check them before you share a report.

### PLAYBOOK.md

A guide to which mode to use for which task. It covers the main thread, `scout`, `researcher`, worktree implementers, `/batch`, agent teams and headless `claude -p` runs. It has three playbooks with prompt templates: research with parallel researchers, large coding tasks with parallel implementers, and comparing design options. It ends with session habits and targets for 30 days.

Its numbers come from one 30-day usage baseline. Measure your own with `analyze_usage_v3.py` before you set targets.

## Manual install (macOS, Linux or by hand)

```sh
mkdir -p ~/.claude/agents ~/.claude/tools
cp agents/*.md ~/.claude/agents/
cp tools/analyze_usage_v3.py tools/PLAYBOOK.md ~/.claude/tools/
```

Then paste `CLAUDE-md-snippet.md` into `~/.claude/CLAUDE.md`. Add the `env` block from `settings.example.json` to `~/.claude/settings.json`, merging it with any `env` block already there. Restart Claude Code.

## Keep .scratch out of git

The agents write logs, notes and handovers to `.scratch/` in the repo they work in. Add it to your global git excludes file so it never shows in `git status`.

PowerShell:

```powershell
git config --global core.excludesFile "$env:USERPROFILE\.gitignore_global"
Add-Content "$env:USERPROFILE\.gitignore_global" '.scratch/'
```

macOS or Linux:

```sh
git config --global core.excludesFile ~/.gitignore_global
echo '.scratch/' >> ~/.gitignore_global
```

If `git config --global core.excludesFile` already prints a path, add `.scratch/` to that file instead.
