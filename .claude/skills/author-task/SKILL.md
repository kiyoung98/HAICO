---
name: author-task
description: Author the HACO task files (task.md, prepare.py, metric.py, evaluate.py, secret/reference.py, baselines.md) to apply HACO to a new domain; ends by running validate_task.sh.
---

# HACO — author a task

Instantiate the fixed **field interface** for a new domain on a fresh branch off
`template`. These are the only per-task files; the orchestrator, subagents, and
slot plumbing are frozen. Read `contract.md` (the `train.py` contract) first.

**The leakage boundary.** Solver-view files must never reach the
held-out; `scripts/validate_task.sh` enforces it.

| File | Solver worktree |
|------|-----------------|
| `task.md`, `prepare.py`, `metric.py`, `baselines.md`, `requirements.txt` | yes |
| `evaluate.py`, `secret/reference.py` | no |

- **`secret/reference.py`** — single `reference()` returning the held-out ground truth.
- **`prepare.py`** — public training surface (dataset / oracle / env / constants) that `train.py` imports. Must not reference `secret/`.
- **`metric.py`** — pure `score(output, reference) -> float`. No file I/O, no paths (may import `prepare` for constants).
- **`evaluate.py`** — sealed scorer CLI: `--run_dir`, loads the artifact + `reference()`, prints the graded line. `score: <float>` is what the harness parses:
  ```python
  print(f"score: {metric.score(artifact, reference())}")
  ```
- **`task.md`** — facts only; no mention of the held-out. Harness-parsed frontmatter + the sections subagents read:
  ```
  ---
  wall_minutes: <int>     # per-node wall-clock budget
  score_noise: <float>    # run-to-run score std
  ---
  ## Task           — one sentence: what train.py must produce
  ## Target access  — `from prepare import <fn>`: shape, return type, differentiable?
  ## Output         — `runs/<run_name>/<file>`: dtype, shape, min count
  ```
- **`baselines.md`** — known baselines and their novelty; `idea` reads it to avoid re-proposing them.

Author success-criteria first: `metric.py` + `secret/reference.py` → `prepare.py`
→ `task.md` → `baselines.md`. Then:

```bash
scripts/validate_task.sh   # fail-closed gate; must pass before bootstrap
```
