#!/usr/bin/env python3
"""Analyze local Claude Code usage from session JSONL files. v3.

v3: de-duplicates repeated usage records. Claude Code writes one JSONL
line per streamed content block of an assistant message; each carries the
same usage object, so v1/v2 over-counted tool-heavy turns. v3 keys on
(message.id, requestId) like ccusage and counts each API call once.
Ratios and avg-ctx were already unaffected; absolute totals now are too.

v2 notes:

v2 changes (based on real-world data where subagent transcripts are stored
as separate files under .../subagents/agent-*.jsonl rather than inline):
  - Files under a "subagents" directory (or named agent-*.jsonl) are treated
    as subagent transcripts and force-classified as subagent tokens.
  - Their tokens are attributed back to a parent session when the records
    carry a parent/session id; otherwise to the owning project.
  - New per-project rollup table (total, subagent share, sessions, agents).
  - "Sessions" now counts human sessions only, not agent files.
  - Per-session avg context estimate: cache-read tokens / assistant turns,
    a proxy for how large the replayed context was.

Usage:
    python3 analyze_usage_v3.py [--days 30] [--root ~/.claude/projects] [--top 10]

Stdlib only; parsing is defensive across Claude Code schema versions.
"""
import argparse, json, os, sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

PARENT_ID_KEYS = ("parentSessionId", "parent_session_id", "sessionId",
                  "session_id", "rootSessionId", "parentUuid")

def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None

def get_usage(rec):
    msg = rec.get("message") or {}
    u = msg.get("usage") or rec.get("usage")
    if not isinstance(u, dict):
        return None, None
    model = msg.get("model") or rec.get("model") or "unknown"
    return u, model

def is_agent_file(relpath, fn):
    parts = relpath.replace("\\", "/").split("/")
    return ("subagents" in parts[:-1]) or fn.startswith("agent-")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--top", type=int, default=10)
    args = ap.parse_args()
    root = os.path.abspath(os.path.expanduser(args.root))
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)

    by_model = defaultdict(lambda: defaultdict(int))
    side_tot = defaultdict(int)
    sessions = {}   # session stem -> stats (human sessions only)
    projects = defaultdict(lambda: {"total": 0, "sub": 0,
                                    "sessions": 0, "agents": 0})
    agent_orphans = []   # (project, parent_ids, total) resolved after walk
    skipped = 0
    seen = set()
    dupes = 0

    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, root)
            parts = rel.replace("\\", "/").split("/")
            project = parts[0] if len(parts) > 1 else "(root)"
            agent = is_agent_file(rel, fn)
            stem = os.path.splitext(fn)[0]

            first = last = None
            total = sub = turns = cache_r = 0
            parent_ids = set()

            try:
                fh = open(path, "r", encoding="utf-8", errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        skipped += 1
                        continue
                    if agent:
                        for k in PARENT_ID_KEYS:
                            v = rec.get(k)
                            if isinstance(v, str) and v and v != stem:
                                parent_ids.add(v)
                    ts = parse_ts(rec.get("timestamp"))
                    if ts:
                        first = ts if first is None or ts < first else first
                        last = ts if last is None or ts > last else last
                    if ts and ts < cutoff:
                        continue
                    u, model = get_usage(rec)
                    if u is None:
                        continue
                    mid = (rec.get("message") or {}).get("id")
                    rid = rec.get("requestId") or rec.get("request_id")
                    if mid and rid:
                        key = (mid, rid)
                        if key in seen:
                            dupes += 1
                            continue
                        seen.add(key)
                    subrec = agent or bool(rec.get("isSidechain"))
                    tot = 0
                    for k in ("input_tokens", "output_tokens",
                              "cache_creation_input_tokens",
                              "cache_read_input_tokens"):
                        v = u.get(k) or 0
                        by_model[model][k] += v
                        tot += v
                    side_tot["subagent" if subrec else "main"] += tot
                    total += tot
                    cache_r += u.get("cache_read_input_tokens") or 0
                    turns += 1
                    if subrec:
                        sub += tot

            if total == 0:
                continue
            projects[project]["total"] += total
            projects[project]["sub"] += sub
            if agent:
                projects[project]["agents"] += 1
                agent_orphans.append((project, parent_ids, total))
            else:
                projects[project]["sessions"] += 1
                sessions[stem] = {"project": project, "first": first,
                                  "last": last, "total": total, "sub": sub,
                                  "turns": turns, "cache_r": cache_r,
                                  "file": fn}

    # Fold agent-file tokens into their parent session where an id matches.
    unattributed = 0
    for project, ids, total in agent_orphans:
        hit = next((s for s in ids if s in sessions), None)
        if hit:
            sessions[hit]["total"] += total
            sessions[hit]["sub"] += total
        else:
            unattributed += total

    def fmt(n):
        return f"{n:,}"

    grand = sum(side_tot.values()) or 1
    cache_reads = sum(u["cache_read_input_tokens"] for u in by_model.values())
    print(f"\n=== Claude Code local usage v3, last {args.days}d "
          f"(root: {root}) ===")
    print(f"Grand total {fmt(grand)} tokens; "
          f"{100*cache_reads/grand:.1f}% are cache reads")

    print("\n-- Tokens by model --")
    for model, u in sorted(by_model.items(),
                           key=lambda kv: -sum(kv[1].values())):
        total = sum(u.values())
        if total == 0:
            continue
        print(f"{model:42s} {fmt(total):>16s} ({100*total/grand:5.1f}%)  "
              f"in {fmt(u['input_tokens'])}, out {fmt(u['output_tokens'])}, "
              f"cw {fmt(u['cache_creation_input_tokens'])}, "
              f"cr {fmt(u['cache_read_input_tokens'])}")

    print("\n-- Main thread vs subagents --")
    for side in ("main", "subagent"):
        t = side_tot.get(side, 0)
        print(f"{side:10s} {fmt(t):>16s}  ({100*t/grand:5.1f}%)")

    print("\n-- By project --")
    rows = sorted(projects.items(), key=lambda kv: -kv[1]["total"])
    for name, p in rows[:max(args.top, 10)]:
        pct = 100 * p["sub"] / p["total"] if p["total"] else 0
        print(f"{fmt(p['total']):>16s}  sub {pct:5.1f}%  "
              f"{p['sessions']:3d} sessions  {p['agents']:3d} agent files  "
              f"{name[:60]}")

    long8 = sum(1 for s in sessions.values()
                if s["first"] and s["last"]
                and (s["last"] - s["first"]) >= timedelta(hours=8))
    print(f"\n-- Sessions -- {len(sessions)} human sessions with usage; "
          f"{long8} spanned 8h+ wall-clock")
    if unattributed:
        print(f"   ({fmt(unattributed)} subagent tokens counted per-project "
              f"only — no parent-session id found in those agent files)")

    print(f"\n-- Top {args.top} sessions by tokens "
          f"(incl. attributed subagents) --")
    for stem, s in sorted(sessions.items(),
                          key=lambda kv: -kv[1]["total"])[:args.top]:
        dur = (s["last"] - s["first"]) if s["first"] and s["last"] else None
        hours = dur.total_seconds() / 3600 if dur else 0
        pct = 100 * s["sub"] / s["total"] if s["total"] else 0
        avg_ctx = s["cache_r"] // s["turns"] if s["turns"] else 0
        print(f"{fmt(s['total']):>16s}  {hours:6.1f}h  sub {pct:5.1f}%  "
              f"~{fmt(avg_ctx):>9s} avg ctx  {s['project'][:38]}/"
              f"{s['file'][:14]}")

    if dupes:
        print(f"\n(de-duplicated {dupes:,} repeated usage records — "
              f"same message id + request id)")
    if skipped:
        print(f"(skipped {skipped} unparseable lines)")
    print()

if __name__ == "__main__":
    sys.exit(main())
