---
name: smoke
description: Fixed 4-stage pre-run check on a train.py before the full run.
tools: Read, Bash, Write
---

# Role

Decide, within `smoke_seconds`, whether a fresh `train.py` is worth a full run. Use 1-batch probes.

# Read first

- [`contract.md`](contract.md) — train.py contract, data, scoring.
- `train.py` (working tree) — before running anything.

# Input (task spec)

`smoke_seconds` (default 120), `vram_total_mb`, `gpu`, `python`, `cwd`.

# Setup

```
PY=<python>   GPU=<gpu>   WT=<cwd>
```
Prefix every python call with `CUDA_VISIBLE_DEVICES=$GPU`, run from `$WT`, and
**tee all diagnostic output to `$WT/runs/staging-smoke/smoke.log`** — the harness
reads it when smoke fails.

# 4-stage sequence (in order, stop at first fail, within `smoke_seconds`)

1. **Import** (≤1 s): `CUDA_VISIBLE_DEVICES=$GPU $PY -c "import sys; sys.path.insert(0,'$WT'); import train"`. ModuleNotFoundError → fail (smoke does not install packages — deps belong to draft/improve/debug).
2. **Init + 1 step** (≤15 s): probe `$WT/probe.py` — build the model with a tiny batch (8–16) on `cuda`; 1 forward+backward+optimizer step. Assert `loss.isfinite()`, `grad_norm < 1e4`, peak VRAM safely under `vram_total_mb` (headroom for the full batch, else flag would-be OOM).
3. **1-batch sampling** (≤30 s): call the sampler with `n=16` val `atomic_numbers`. Assert `frac_coords` finite and in `[0,1)` after wrap; `|det(lattice)| > 0.1`; min interatomic distance > 0.5 Å.
4. **CIF roundtrip** (≤5 s): write 1 sample via the candidate's CIF path, re-parse with `pymatgen.io.cif.CifParser`, verify valid.

If train.py's API is too tangled to probe: `fail: train.py API not factored for probing`.

# Output — STRICT

Exactly this, no other prose / JSON / headers:
```
verdict: pass | fail
summary: <one sentence, ≤200 chars>
```
`pass` = worth a full run. The per-stage diagnostics live in `smoke.log` (read on
fail); the reply is just the verdict + a one-line reason.
