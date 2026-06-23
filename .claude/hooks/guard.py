#!/usr/bin/env python3
"""PreToolUse guard for the unattended (bypass-permissions) HACO loop.

Runs even under --dangerously-skip-permissions. HARD-BLOCKS (exit 2) any attempt
to modify the harness / scoring surface or to `git push`, and lets everything
else through (exit 0). Deny-only: never prompts, so the loop never stalls.
Fail-CLOSED: any unparseable input or internal error denies (exit 2) instead of
allowing — a spurious deny only downgrades one write to a [BUGGY] node (the loop
recovers via run_or_bug), whereas a spurious allow could breach the sealed surface.

GENERIC: this guard carries NO per-task knowledge. It only write-protects the
fixed harness surface and blocks git push. Held-out leakage is prevented by
*construction* (the solver view never contains secret/ — see README.md), not by
matching task-specific tokens here. The Bash regexes below are defense-in-depth
for accidental writes, not an airtight sandbox; the seal is the absence of secret/.

Protected (write-only-denied to the loop), matched on the main repo AND
worktree copies:
  - files named: evaluate.py, prepare.py, metric.py, requirements.txt,
    contract.md, task.md
  - anything under a  scripts/ , .claude/ , data/ , or  secret/  directory
  - bash `git push` (only as a real command, not a substring in a message),
    and redirects (> / >>) into any of the above
Legitimate writes (train.py in a worktree, events.log, runs/*) are untouched.
"""
import sys, json, re

PROTECTED_NAMES = {"evaluate.py", "prepare.py", "metric.py", "requirements.txt",
                   "contract.md", "task.md"}
PROTECTED_DIRS = {"scripts", ".claude", "data", "secret"}


def deny(reason):
    sys.stderr.write("BLOCKED by guard.py: " + reason + "\n")
    sys.exit(2)


def path_protected(p):
    if not p:
        return False
    parts = p.replace("\\", "/").split("/")
    if parts[-1] in PROTECTED_NAMES:
        return True
    return any(seg in PROTECTED_DIRS for seg in parts[:-1])


def main():
    data = json.loads(sys.stdin.read())
    if not isinstance(data, dict):
        deny("malformed hook input (not a JSON object)")
    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
        p = ti.get("file_path") or ti.get("notebook_path") or ""
        if path_protected(p):
            deny("protected harness/scoring path is read-only: " + p)
        if p.endswith('.py') and not (p.endswith('/train.py') or p == 'train.py'):
            deny("only train.py may be written — put all code in train.py")

    elif tool == "Bash":
        cmd = ti.get("command", "") or ""
        # `git push` only when it starts a command segment, not inside a message.
        if re.search(r"(?:^|[\n;&|])\s*git\s+push\b", cmd):
            deny("git push is forbidden for the autonomous loop")
        for name in PROTECTED_NAMES:
            if re.search(r">>?\s*\S*" + re.escape(name) + r"\b", cmd):
                deny("redirect into protected file is forbidden: " + name)
        if re.search(r">>?\s*(?:[^\s]*/)?(?:scripts|\.claude|data|secret)/", cmd):
            deny("redirect into protected directory is forbidden")
        if re.search(r"\S*python3?\S*[^\n]*\btrain\.py\b", cmd):
            deny("direct execution of train.py is forbidden -- write train.py and return; the harness runs it")
        if re.search(r"\S*python3?\S*\s+-c\b", cmd):
            deny("direct python execution is forbidden -- write train.py and return; use uv pip install for packages")

    sys.exit(0)


try:
    main()
except Exception as e:  # fail CLOSED: an unparseable/unexpected input must not slip through
    sys.stderr.write("BLOCKED by guard.py: internal error, failing closed: "
                     + repr(e) + "\n")
    sys.exit(2)
