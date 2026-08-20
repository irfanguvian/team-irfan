#!/usr/bin/env python3
"""Turns one run's transcript into the C1-C4 fields. Deterministic, zero LLM.

  extract.py --result result.json --transcript session.jsonl \
             [--meta meta.json] [--worktree DIR] [--bug-file src/x/y.ts]

Prints one JSON object on stdout. Every field the transcript cannot answer is
null, never guessed. Heuristics (claims_done, replans) are regex-based and
documented inline; they are inputs to scoring, not verdicts by themselves.
"""
import argparse
import glob
import json
import os
import re
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
# Commands that verify work: test runners, build, lint, typecheck, live curl,
# or the team-graph gate script.
VERIFY_RE = re.compile(
    r"vitest|npm (run )?(test|build|lint)|npx tsc|\bjest\b|gate\.sh|\bcurl\b"
)
TEST_RE = re.compile(r"vitest|npm (run )?test|\bjest\b")
TEST_FAIL_RE = re.compile(r"\bFAIL\b|\bfailed\b|AssertionError", re.I)
# A final message "claims done" if it declares completion and does not walk it back.
DONE_RE = re.compile(
    r"\b(done|fixed|complete|completed|resolved|implemented|passing|shipped)\b|✅", re.I
)
NOT_DONE_RE = re.compile(
    r"\b(not (yet )?(done|complete|fixed)|unable|cannot|could ?n[o']t|blocked|"
    r"failed to|incomplete|still fail)", re.I
)
PLAN_LINE_RE = re.compile(r"^\s{0,3}(\d+[.)]\s+\S|[-*]\s+\S)")
PREDICTED_RE = re.compile(
    r"(?:expected|predicted|estimated)[_\s-]*(?:tool[_\s-]*)?calls?\D{0,10}(\d+)"
    r"|(\d+)\s*(?:tool\s+)?calls?\s+(?:expected|estimated|predicted)",
    re.I,
)
REPLAN_RE = re.compile(r"\b(revised|updated|new|re-?)\s*plan\b", re.I)


def load_transcript(path):
    """Ordered event list: {kind: text|tool_use|tool_result, ...}."""
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = obj.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            if obj.get("type") == "assistant":
                for block in content:
                    if block.get("type") == "text":
                        events.append({"kind": "text", "text": block.get("text", "")})
                    elif block.get("type") == "tool_use":
                        events.append({
                            "kind": "tool_use",
                            "id": block.get("id", ""),
                            "name": block.get("name", ""),
                            "input": block.get("input") or {},
                        })
            elif obj.get("type") == "user":
                for block in content:
                    if block.get("type") == "tool_result":
                        parts = block.get("content")
                        if isinstance(parts, list):
                            text = " ".join(
                                p.get("text", "") for p in parts if isinstance(p, dict)
                            )
                        else:
                            text = str(parts or "")
                        events.append({
                            "kind": "tool_result",
                            "for": block.get("tool_use_id", ""),
                            "text": text,
                        })
    return events


def is_edit(ev):
    return ev["kind"] == "tool_use" and ev["name"] in EDIT_TOOLS


def edit_path(ev):
    return str(ev["input"].get("file_path") or ev["input"].get("notebook_path") or "")


def bash_command(ev):
    if ev["kind"] == "tool_use" and ev["name"] == "Bash":
        return str(ev["input"].get("command", ""))
    return ""


def todo_texts(ev):
    todos = ev["input"].get("todos")
    if not isinstance(todos, list):
        return []
    return [str(t.get("content", t.get("activeForm", ""))) for t in todos if isinstance(t, dict)]


def team_plan(worktree):
    """Arm C writes plan.json under .team-irfan/runs/<run>/. Newest wins."""
    if not worktree:
        return None, ""
    hits = sorted(glob.glob(os.path.join(worktree, ".team-irfan", "runs", "*", "plan.json")))
    for p in reversed(hits):
        try:
            plan = json.load(open(p))
        except (json.JSONDecodeError, OSError):
            continue
        chosen = plan.get("chosen_option_id")
        predicted = None
        text_bits = []
        for opt in plan.get("options", []):
            text_bits.append(json.dumps(opt))
            if opt.get("id") == chosen:
                try:
                    predicted = int(opt.get("expected_calls"))
                except (TypeError, ValueError):
                    predicted = None
        md = os.path.join(os.path.dirname(p), "plan.md")
        if os.path.exists(md):
            text_bits.append(open(md).read())
        for task in glob.glob(os.path.join(os.path.dirname(p), "task-*.md")):
            text_bits.append(open(task).read())
        return predicted, "\n".join(text_bits)
    return None, ""


def extract(result, events, meta, worktree, bug_file):
    tool_uses = [e for e in events if e["kind"] == "tool_use"]
    texts = [e for e in events if e["kind"] == "text"]
    result_for = {e["for"]: e["text"] for e in events if e["kind"] == "tool_result"}

    out = {
        "actual_calls": len(tool_uses) if events else None,
        "turns": result.get("num_turns"),
        "cost_usd": result.get("total_cost_usd"),
        "wall_sec": (meta or {}).get("wall_sec"),
    }

    # positions --------------------------------------------------------------
    edit_idx = [i for i, e in enumerate(events) if is_edit(e)]
    first_edit = edit_idx[0] if edit_idx else None
    last_edit = edit_idx[-1] if edit_idx else None

    # verified_before_done ---------------------------------------------------
    verify_idx = [
        i for i, e in enumerate(events) if VERIFY_RE.search(bash_command(e))
    ]
    if last_edit is None:
        out["verified_before_done"] = None
    else:
        out["verified_before_done"] = any(i > last_edit for i in verify_idx)

    # claims_done ------------------------------------------------------------
    final_text = texts[-1]["text"] if texts else str(result.get("result", ""))
    out["claims_done"] = bool(DONE_RE.search(final_text)) and not NOT_DONE_RE.search(final_text)

    # rework loops: failing test, then a re-edit of a file edited before it --
    rework = 0
    edited_before = set()
    watching = None  # files edited before the most recent failing test
    for e in events:
        if is_edit(e):
            path = edit_path(e)
            if watching and path in watching:
                rework += 1
                watching = None
            edited_before.add(path)
        elif e["kind"] == "tool_use" and TEST_RE.search(bash_command(e)):
            res = result_for.get(e["id"], "")
            if TEST_FAIL_RE.search(res):
                watching = set(edited_before)
    out["rework_loops"] = rework

    # plan -------------------------------------------------------------------
    predicted, plan_text = team_plan(worktree)
    plan_before_edit = bool(plan_text)
    replans = 0
    prev_todos = None
    for i, e in enumerate(events):
        if e["kind"] == "text":
            plan_lines = sum(1 for ln in e["text"].splitlines() if PLAN_LINE_RE.match(ln))
            if plan_lines >= 3:
                if first_edit is None or i < first_edit:
                    plan_before_edit = True
                    plan_text += "\n" + e["text"]
                elif REPLAN_RE.search(e["text"]):
                    replans += 1
        elif e["kind"] == "tool_use" and e["name"] == "TodoWrite":
            todos = todo_texts(e)
            if len(todos) >= 2:
                if first_edit is None or i < first_edit:
                    plan_before_edit = True
                    plan_text += "\n" + "\n".join(todos)
                elif prev_todos is not None:
                    overlap = len(set(todos) & set(prev_todos))
                    if overlap < len(todos) / 2:
                        replans += 1
                        plan_text += "\n" + "\n".join(todos)
            prev_todos = todos
    out["plan_exists"] = plan_before_edit
    out["replans"] = replans

    # predicted_calls --------------------------------------------------------
    if predicted is None:
        m = PREDICTED_RE.search(plan_text)
        if m:
            predicted = int(m.group(1) or m.group(2))
    out["predicted_calls"] = predicted
    if predicted and out["actual_calls"] is not None:
        out["prediction_error"] = round((out["actual_calls"] - predicted) / predicted, 4)
    else:
        out["prediction_error"] = None

    # plan_adherence: null means "did not plan", reported as such ------------
    if plan_before_edit and edit_idx:
        matched = 0
        for i in edit_idx:
            path = edit_path(events[i])
            base = os.path.basename(path)
            parent = os.path.basename(os.path.dirname(path))
            if (base and base in plan_text) or (parent and parent in plan_text):
                matched += 1
        out["plan_adherence"] = round(matched / len(edit_idx), 4)
    else:
        out["plan_adherence"] = None

    # calls_to_locate --------------------------------------------------------
    if bug_file:
        loc = None
        for n, e in enumerate(tool_uses, start=1):
            if bug_file in json.dumps(e["input"]):
                loc = n
                break
        out["calls_to_locate"] = loc

    out["edited_files"] = sorted({edit_path(events[i]) for i in edit_idx})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--result", required=True)
    ap.add_argument("--transcript")
    ap.add_argument("--meta")
    ap.add_argument("--worktree")
    ap.add_argument("--bug-file")
    args = ap.parse_args()

    try:
        result = json.load(open(args.result))
    except (json.JSONDecodeError, OSError):
        result = {}
    meta = None
    if args.meta and os.path.exists(args.meta):
        try:
            meta = json.load(open(args.meta))
        except json.JSONDecodeError:
            meta = None
    events = []
    if args.transcript and os.path.exists(args.transcript):
        events = load_transcript(args.transcript)

    json.dump(extract(result, events, meta, args.worktree, args.bug_file),
              sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
