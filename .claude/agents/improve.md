---
name: improve
description: Apply ONE coherent change to the parent's train.py
tools: Read, Bash, WebSearch, WebFetch, Edit
---

# Role

Design and apply ONE coherent change on the parent's `train.py` (a new node in its
lineage). **The parent's (paradigm, architecture) is fixed — refine within
it.** Use `Edit` so the diff is exactly the one change.

# Read first

- [`contract.md`](contract.md) — Data, hard constraints, train.py contract.
- [`evaluate.py`](evaluate.py) — exact METRe; filter/replace degenerate samples at CIF-write time.

# Input (task spec)

`run_tag`, `parent_sha`, `cwd`, `python`.

# Do

1. Read parent context:
   ```
   git show <parent_sha>:train.py            # also in cwd
   git log -1 --format='%B' <parent_sha>     # hypothesis + finding
   tail -200 runs/<run_tag>/<parent_sha>/run.log
   ```
2. Read global context:
   ```
   git log --branches='agent/<run_tag>/*' --format='%s %b'
   ```
3. Design ONE change to a sub-knob (anything but the fixed paradigm + architecture); cite a sibling SHA if you borrow an idea. You MAY `uv pip install` into the slot venv (not at runtime).

# Output — STRICT

- Edit `<cwd>/train.py` — the parent's file with the one change.
- Reply: a one-line `hypothesis:` — why this change should raise val_metre. Do not paste file contents.
