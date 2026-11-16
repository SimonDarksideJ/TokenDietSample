# Claude Code operating playbook

Which mode to use for which task, with prompt templates. Derived from your Aug-2026 30-day baseline (v3, de-duplicated: 3.73B tokens). Companion to the agents in `%USERPROFILE%\.claude\agents\` and the CLAUDE.md snippet.

## 1. What you are actually paying for

- 97% of tokens are cache reads, i.e. replayed context. Output — the actual work — is under 0.4% of tokens. Using Opus-4-class price ratios (cache read ≈ 10% of input, output ≈ 5×), replayed context is still roughly 70% of equivalent spend and output roughly 10%. You are paying to *carry* context, not to *produce* work.
- Every one of your top-10 sessions ran at 220k–511k average context. Nothing at that size is cheap on any model.
- 73% of the month is one repo (MechCommander2-MG on E: and C:); 47% is one 11-hour session (`10499cf6`: 1.76B tokens, 85.8% subagent, ~511k avg context in the lead). Ten of your 67 sessions account for 89% of the month. Session `0e9af0c1` spans 362 wall-clock hours — one conversation resumed for two weeks at ~220k context.
- Delegation is inverted. Coding sessions delegate heavily on top-tier models under a bloated lead; research sessions barely delegate (0% subagent share) and do all reading in the main thread at 265–420k context.

Rule of thumb: **cost ≈ context size × turns × model rate.** You control all three. Subagents fix the first only if the lead stays thin and the agents are cheap; otherwise they multiply the third.

## 2. Mode selection

| Situation | Use | Why |
|---|---|---|
| A grep/read answers it | Main thread, no agent | One tool call beats one agent |
| Read-only fact-finding, several independent questions | `scout` × ≤3, background | Exploration stays out of your context; haiku |
| Web/spec/docs research, several independent topics | `researcher` × ≤3, notes to `.scratch/research/` | Fetched pages never enter the lead |
| One coherent multi-step change | Single session, plan mode first | Steps depend on each other; agents can't share context |
| Several independent code changes with separate file ownership | `implementer` subagents (`isolation: worktree`) or manual `claude --worktree` sessions | Filesystem isolation, no edit collisions |
| 10+ similar mechanical changes (migration, API rename) | `/batch` → many worktree agents on haiku/sonnet | Built for fan-out; each agent tests + PRs independently |
| Competing designs/hypotheses that must challenge each other | Agent team (experimental), 3–5 teammates on sonnet | Only case that justifies inter-agent messaging |
| Recurring gated check | `validator` subagent, or headless `claude -p` | Logs to file, returns pass/fail |
| Anything left running unattended | Headless `claude -p ... --max-turns N`, never interactive | Fresh context per run, dies when done |

## 3. When to stay in a single session

Stay single-threaded when: the next step depends on the last result; edits touch the same files; you would need to paste more than a paragraph of context into the agent prompt for it to work; or the whole task is under ~10 tool calls.

The cost of a subagent is a fresh context (CLAUDE.md + tool definitions + re-reading files) plus its report landing in the lead. It pays off only when the agent's *exploration* would otherwise land in your main context and stay there for the rest of the session. That is exactly your research pattern — so research is where you are *under*-delegating.

## 4. Playbook A — Research with parallel search

Current failure mode: 0% subagents, 265–420k main context, 3–11 hours; the lead reads everything itself.

1. Frame first. Write 3–6 concrete questions to `.scratch/research/questions.md` before any searching. Vague mandates ("investigate WebXR on Samsung") are what make agents grind for an hour.
2. Fan out ≤3 `researcher` agents, one question each, in the background. Each writes `.scratch/research/<question>.md` (sources, dates, confidence) and returns ≤15 lines.
3. The lead reads only the summaries and synthesises into `.scratch/research/decision.md`. Second round only on open items, again as scoped questions.
4. `/clear` between research topics. The notes files are the memory; the conversation is not.
5. Platform matrices (your WebXR work): one researcher per platform with the *same* question set, then one "compare" step that reads only the notes files.

Template:
```
Spawn 3 researcher agents in the background, one per question in .scratch/research/questions.md (Q1–Q3).
Each writes its notes to .scratch/research/q<N>.md and replies with ≤15 lines: findings + source URLs + confidence.
Do not read the notes files yourself until all three return; then give me a one-page synthesis and list what remains unverified.
```

## 5. Playbook B — Large-project coding with parallel agents (MechCommander2)

Current failure mode: one lead at ~511k context spawning ~90 agents on opus/fable, over 11 hours.

1. Plan mode (Shift+Tab) in the lead. Output a task list with explicit file ownership per task; write it to `.scratch/plan.md`. Tasks that share files are one task.
2. Keep the lead thin. It does not read large files; exploration goes through `scout`. The lead's job is planning, dispatch, merge decisions.
3. Independent tasks → `implementer` subagents (sonnet, worktree-isolated, capped at 60 turns), ≤3 at a time. Each implements, builds, tests, commits on its own branch, returns ≤20 lines including the branch name.
4. `validator` gate per branch, then merge (you or the lead). A merge conflict means the task split was wrong — fix the split, not the conflict.
5. `/compact keep: plan.md status, open branches, decisions` after each merge round. `/clear` when the plan moves to a new phase, then re-point the fresh session at `plan.md`.
6. Never `--resume` a coding session across days. Fresh session + `plan.md` beats a two-week conversation every time.

For 10+ similar mechanical changes use `/batch`: it interviews you, then fans the work out to as many worktree agents as needed, each testing and opening a PR independently. Set the model to haiku/sonnet in the interview.

Template:
```
Read .scratch/plan.md. Tasks T3, T4, T5 are independent (file ownership listed per task).
Spawn one implementer agent per task, in the background, worktree-isolated. Each: implement only its listed files, build, run the relevant tests, commit on its branch, and report branch + files + PASS/FAIL in ≤20 lines.
Do not implement anything yourself. When all three return, run validator on each branch and give me a merge order.
```

## 6. Playbook C — Coding research with multiple outputs (design options)

Three variants, in ascending cost:

**Options as documents.** 2–3 `scout`/`researcher` agents each write a proposal to `.scratch/options/<n>.md` against the same rubric (approach, files touched, risks, effort estimate, unknowns). The lead builds the comparison from the files. Cheapest; use this first.

**Options as code (spikes).** One `implementer` per option, each in its own worktree, sonnet, turn-capped. Each produces a working diff plus a short `RESULT.md` (what worked, what didn't, measurements). `validator` runs each; you or the lead compares; losing branches are discarded. This is the correct use of worktrees. It is not the place for opus.

**Options that must argue with each other.** Real ambiguity or a root-cause hunt where anchoring is the risk. Agent team, 3–5 teammates on sonnet: "investigate different hypotheses, try to disprove each other, write consensus to `.scratch/findings.md`". Enable by adding `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"` to the `env` block in `%USERPROFILE%\.claude\settings.json`; set **Default teammate model** to sonnet in `/config` (teammates do not inherit the lead's model). In-process mode works in the VS Code terminal; split panes do not on Windows/VS Code. Expect materially higher token use; this is the exception, not the default.

Template (spikes):
```
Two candidate approaches for <problem>: A = <one line>, B = <one line>.
Spawn two implementer agents, one per approach, each worktree-isolated. Each builds a minimal working spike, runs <benchmark/test>, writes RESULT.md with measurements, commits, and reports in ≤20 lines.
Then run validator on both and give me a comparison table from the two RESULT.md files. Do not read the diffs yourself unless the results disagree.
```

## 7. Session hygiene — the habits

- Session = task. `/clear` at boundaries. Do not resume a conversation for weeks.
- `/context` when a session feels heavy; `/compact <keep-list>` around 60% full, not at auto-compact.
- Files are memory: `.scratch/` notes, `plan.md`, `findings.md`. Keep `.scratch/` out of git (global excludes file — see README).
- Anything unattended runs headless with `--max-turns`.
- Model discipline: lead on opus only when the reasoning is genuinely hard; delegated work on sonnet/haiku; `CLAUDE_CODE_SUBAGENT_MODEL` = sonnet in `%USERPROFILE%\.claude\settings.json` (`env` block, set by the installer) as the backstop; teammate default set to sonnet in `/config`.
- Cap turns: `maxTurns` in agent frontmatter (already set in the pack), `--max-turns` on headless runs.
- One repo location. MechCommander2 exists on both E: and C:; pick one so CLAUDE.md, agents, and `.scratch/` live in one place.
- Weekly: `py "%USERPROFILE%\.claude\tools\analyze_usage_v3.py" --days 7`. Watch three numbers: haiku+sonnet share of the by-model table (currently ~1%), avg ctx on top sessions (currently 220k–511k), and top-session concentration.

## 8. Targets for the next 30 days

- Haiku+sonnet ≥ 50% of subagent tokens.
- No session above ~200k average context.
- No single session above ~15% of the month.
- Zero sessions spanning >24h wall-clock.
