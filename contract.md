# HACO contract (read by every subagent)

**Run isolation**: each autoresearch run is one campaign tagged
`<run_tag>`; its nodes live under `agent/<run_tag>/*` branches.
`git log --branches='agent/<run_tag>/*' --oneline` is the per-run memory.
Never pull strategies, findings, or train.py from another run's branches.

## Task — the field interface

The task is defined by **`task.md`** (the prose contract) over the
domain-agnostic skeleton below. Read
`task.md` and `metric.py` before writing or judging a `train.py`. Every task,
in any domain, fills the same fields:

1. **Target surface** — what `train.py` may use: `prepare.py` exposes it
   (a dataset, an oracle/energy callable, an environment, plus any *public*
   conditioning signal). This is the ONLY task input. Run once at bootstrap;
   read-only thereafter. `prepare.py` is **public** — it never names or loads
   the held-out answer.
2. **Held-out** — the ground truth, in `secret/` (e.g. `secret/reference.py`).
   It is **never present in the solver's worktree** and must never be reached
   by `train.py`. It exists only for the scorer.
3. **Output artifact** — `train.py` writes it under `runs/<run_name>/` in the
   layout `task.md` defines. That is the whole job.
4. **Metric** — `metric.py` is the pure scoring function `score(output,
   reference)`. It is public and path-free: you MAY read it to know exactly how
   you are graded (that is fair). `evaluate.py` is the **sealed scorer**: it
   loads your artifact + the held-out reference and runs `metric.py`. The
   **harness** runs `evaluate.py` after your run.
5. **Protocol** — the hard constraints below.

Anything else — train/val/test splits, the exact conditioning signal, the
output format — is task-specific and stated in `task.md`, not assumed here.

## Protocol (hard constraints — never violate)

- **Editable**: `train.py` only.
- **Read-only by convention** (do NOT modify): `prepare.py`, `metric.py`,
  `evaluate.py`, `task.md` (task spec),
  `requirements.txt` (the file; the *environment* may be extended via
  slot-local `uv pip install` — see below). `evaluate.py`, `secret/`, and the
  held-out data are not present in your worktree at all.
- **`baselines.md`** (novelty boundary): existing entries are immutable for everyone;
  `draft` MAY APPEND a prior-art entry found during falsification.
- **Slot venv extension**: draft / improve / debug may `uv pip install` into
  their slot venv before writing train.py. The venv is isolated; added packages
  are frozen at finalize and inherited by children. train.py must NOT pip
  install at runtime.
- **Subagents never run Python**: draft / improve / debug only author `train.py`
  — never execute it, or any other Python, to test. It runs only via
  `scripts/slot_run.sh` (full run), which pins the GPU. An unpinned subagent run
  lands on GPU 0 and bypasses the harness.
- **No leakage — by construction**: `train.py` may use only what `prepare.py`
  exposes and the inputs `task.md` permits. The held-out ground truth lives in
  `secret/`, is not on the solver's filesystem, and must never be read,
  re-downloaded, or reconstructed. The runtime has **no network** (see below),
  so a publicly-sourced reference cannot be re-fetched. Knowing the metric
  (`metric.py`) is fine; reaching the answer is not. Producing the artifact
  from the target surface alone is the entire task.
- **VRAM**: keep `peak_vram_mb` safely under `vram_total_mb` (per-GPU total,
  in your task spec), leaving headroom for fragmentation / allocator slack —
  an OOM wastes the whole run. The margin is your judgment.

## train.py contract

### Wall-clock budget

`train.py` gets a single total budget `--max_minutes` and self-allocates it
between training and producing the output artifact: poll the wall-clock and
stop training in time to write `runs/<run_name>/` before the cap. There is no
separate output window — a node that trains to the deadline and emits nothing
just scores `nan` (a `[BUGGY]` node), so leaving output time is your own
incentive. **Scoring is a separate, sealed harness step (`scripts/slot_score.sh`
→ `evaluate.py`) after the cap.**

**`wall_minutes` is fixed per campaign (from `task.md`, overridable at launch)
and uniform across all nodes; train.py must enforce it, and the authoring subagents
(`draft` / `improve` / `debug`) must not raise it.**

### Required CLI + outputs

- CLI flags: `--max_minutes <float>` (total wall-clock budget), `--run_name <str>`.
- Inputs: only what `prepare.py` exposes and `task.md` permits.
- Output write path: under `runs/<run_name>/`, in the layout `task.md` defines.
- Single GPU only. The harness sets `CUDA_VISIBLE_DEVICES`; just use `cuda`.
- Self-contained at runtime: **no pip install and no network** inside train.py.
- **No model checkpoints / no auxiliary file writes.** Forbid
  `torch.save(model.state_dict(), ...)`, EMA-save, optimizer-state-save,
  `lightning.save_checkpoint`, `model.save_pretrained`, etc. The only output is
  the artifact under `runs/<run_name>/`. No writes outside `runs/<run_name>/`.

### Required print at end

`train.py` MUST print an artifact-ready marker and may print VRAM (kept in
`run.log`, informational, not parsed):

```
---
artifact:         runs/<run_name>/<path>      # what the scorer should grade
peak_vram_mb:     <float>                       # informational
```

The graded `score:` line is emitted by `evaluate.py` via `slot_score.sh`, and
`slot_run.sh`'s run tail greps `^score:` from the **scorer's** output — not from
`train.py`. Higher is better unless `task.md` / `metric.py` states otherwise.
