#!/usr/bin/env python3
"""PreToolUse guard for the unattended (bypass-permissions) HACO loop.

Runs even under --dangerously-skip-permissions. HARD-BLOCKS (exit 2) any attempt
to modify the harness / scoring surface or to `git push`, and lets everything
else through (exit 0). Deny-only: never prompts, so the loop never stalls.
Fail-open on internal error so a hook bug can't break the run.

Protected (read-only to the loop), matched on the main repo AND worktree copies:
  - files named: evaluate.py, prepare.py, requirements.txt, program.md, contract.md
  - anything under a  scripts/  or  .claude/  or  data/  directory
  - bash `git push` (only as a real command, not a substring in a message),
    and redirects (> / >>) into any of the above
Legitimate writes (train.py in a worktree, .slots/*, runs/*) are untouched.
"""
import sys, json, re

PROTECTED_NAMES = {"evaluate.py", "prepare.py", "requirements.txt",
                   "program.md", "contract.md"}
PROTECTED_DIRS = {"scripts", ".claude", "data"}


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
    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
        p = ti.get("file_path") or ti.get("notebook_path") or ""
        if path_protected(p):
            deny("protected harness/scoring path is read-only: " + p)

    elif tool == "Bash":
        cmd = ti.get("command", "") or ""
        # `git push` only when it starts a command segment, not inside a message.
        if re.search(r"(?:^|[\n;&|])\s*git\s+push\b", cmd):
            deny("git push is forbidden for the autonomous loop")
        for name in PROTECTED_NAMES:
            if re.search(r">>?\s*\S*" + re.escape(name) + r"\b", cmd):
                deny("redirect into protected file is forbidden: " + name)
        if re.search(r">>?\s*(?:[^\s]*/)?(?:scripts|\.claude|data)/", cmd):
            deny("redirect into protected directory is forbidden")
        for name in PROTECTED_NAMES:
            if re.search(
                r"(?:^|[\n;&|`(])\s*(?:cp|mv|sed\s+-\S*i)\s[^\n]*\b" + re.escape(name) + r"\b",
                cmd
            ):
                deny("write-capable command targeting protected file: " + name)

    sys.exit(0)


try:
    main()
except Exception:
    sys.exit(0)  # fail open: never break the loop on a hook error
