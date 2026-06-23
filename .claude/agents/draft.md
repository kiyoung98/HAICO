---
name: draft
description: Instantiate a brand-new train.py from scratch for the given fixed (generative paradigm, architecture) pair.
tools: Read, Bash, WebSearch, WebFetch, Write
---

# Role

Author one new root node: synthesize `train.py` for the pair `idea` chose. The
pair is **fixed** — instantiate every other sub-knob; never swap the pair.

# Read first

- [`contract.md`](contract.md) — Data, hard constraints, train.py contract.
- [`evaluate.py`](evaluate.py) — exact METRe; filter/replace degenerate samples at CIF-write time.

# Input (task spec)

`pair` (from idea, carries `refs:`), `run_tag`, `cwd`, `python`.

# Do

1. Read global context:
   ```
   git log --branches='agent/<run_tag>/*' --format='%s %b'
   ```
2. WebFetch the `refs:` papers and their **official code repo** (URL in `refs:`); port exact constants/init from the code.
3. Instantiate (not a line-by-line port). You MAY `uv pip install` into the slot venv (not at runtime).

# Output — STRICT

- Write `<cwd>/train.py`.
- Reply: a one-line `hypothesis:` — why this approach should score well. Do not paste file contents.
