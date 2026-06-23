---
name: draft
description: Pick a novel method and implement its train.py.
tools: Read, Bash, WebSearch, WebFetch, Write, Edit
model: claude-opus-4-8
---

# Role

Choose a novel method, then implement `train.py` for it. Once chosen the method is
fixed — instantiate every sub-knob.

# Read

- contract.md, task.md — first
- baselines.md — first; re-scanned per candidate in step 3
- runs/<run_tag>/directives.md — after the tree, before picking the method

# Input (task spec)

`{run_tag, cwd, python}`.

# Do

1. Read the tree for context:
   ```
   scripts/tree_view.sh <run_tag> 
   ```
2. Pick ONE candidate method, via broad cross-field WebSearch and WebFetch, which is transferable
   to this task, not in `baselines.md` and not already in the tree. `refs:` ≥ 2 papers,
   each with its official code repo URL when one exists.
3. Novelty falsification — BEFORE writing any code. Re-scan `baselines.md` for the candidate and CHECK whether the method has already been applied to the same problem on any benchmark with WebSearch + WebFetch. If it IS prior art:
     a. APPEND its entry to `baselines.md`.
     b. Discard this candidate and return to step 2.
   Loop until a candidate SURVIVES.
4. Implement a survivor against our interface.

# Output — STRICT

- Write `<cwd>/train.py` (the only code file).
- Write the chosen `<method>; refs: …` line to `<cwd>/runs/staging/method`.
- Write a one-line `hypothesis:` (why it should score well) to `<cwd>/runs/staging/hypothesis`.
