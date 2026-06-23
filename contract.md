# HACO contract (read by every subagent)

**Run isolation**: each autoresearch run is one campaign tagged
`<run_tag>`; its nodes live under `agent/<run_tag>/*` branches.
`git log --branches='agent/<run_tag>/*' --oneline` is the per-run memory.
Never pull strategies, findings, or train.py from another run's branches.

## Data

Three split files `data/mp20_ps_{train,val,test}.pt`, each a
`torch.load`-able `list[dict]`. Record schema:

| key | dtype | shape | note |
|---|---|---|---|
| `lattice` | `float32` | `[3, 3]` | basis matrix in Å, rows = a, b, c |
| `frac_coords` | `float32` | `[N, 3]` | in `[0, 1)` |
| `atomic_numbers` | `int64` | `[N]` | atomic number Z |

`N` is variable per record, empirically `N ∈ [1, 20]`. Batching must
accept variable `N`.

| split | count | use |
|---|---|---|
| train | 27137 | gradient updates |
| val | 9060 | sample conditioning on `atomic_numbers` only; score via `evaluate.py` |
| test | held out | do not access during search |

**Polymorph split**: polymorphs of the same composition stay on the
same side, so `p(structure | composition)` is genuinely multi-modal.

**Niggli-reduced cells (data prior)**: every `lattice` matrix in the
three splits is Niggli-reduced -- all cell angles lie in `[60°, 120°]`
(float ε aside).

**Scoring**: `evaluate.py` uses pymatgen
`StructureMatcher(ltol=0.3, stol=0.5, angle_tol=10°)`.

**Sample output contract**: 9060 CIFs at
`runs/<run_name>/val_samples/{idx:05d}.cif`, idx-aligned with the val
record order, in canonical form (lattice `[3, 3]` Å,
`frac_coords ∈ [0, 1)`, integer Z).

## Protocol (hard constraints — never violate)

- **Editable**: `train.py` only.
- **Read-only by convention** (do NOT modify):
  - `evaluate.py` (val-hardcoded scorer)
  - `prepare.py`
  - `requirements.txt` (the file itself; the *environment* may be extended
    via slot-local `uv pip install` by draft / improve / debug — see below)
- **Slot venv extension**: draft / improve / debug may `uv pip install` into
  their slot venv before writing train.py. The venv is isolated; added packages
  are frozen at finalize and inherited by children. train.py must NOT pip
  install at runtime.
- **Operators never run `train.py`**: draft / improve / debug only author it;
  it runs only via `smoke` (probes) and `scripts/slot_run.sh`, which pin the GPU.
  An unpinned operator run lands on GPU 0 and bypasses the harness.
- **Training data**: only `mp20_ps_train.pt`. The model and the training
  loop must never read `mp20_ps_val.pt` or `mp20_ps_test.pt`.
- **Validation data**: `mp20_ps_val.pt` is **only** accessed after training
  has finished, and **only** the per-record `atomic_numbers` (composition)
  may be passed to the sampler.
- **Test data**: untouched. Reserved for the public leaderboard.
- **Scoring**: `evaluate.py` always computes METRe against the full val
  split (n=9060). Do not subset or alias.
- **VRAM**: keep `peak_vram_mb` safely under `vram_total_mb` (per-GPU
  total, in your task spec), leaving headroom for fragmentation / allocator
  slack — an OOM wastes the whole run. The margin is your judgment.

## train.py contract

### Stage-wise wall-clock budget

Train.py runs three stages in sequence: training → sampling → evaluate.
Each has its own wall-clock cap, all enforced by train.py itself.

| Stage | Cap | Meaning |
|---|---|---|
| Training | **`--max_minutes`** (default 120) | CLI flag — train.py polls its training-loop wall-clock and exits the loop *immediately* once the cap is reached, regardless of epoch / step count. |
| Sampling | **`--sample_minutes`** (default 60) | After training, train.py has this long to produce up to 9060 CIFs. If the budget is reached early, write the partial set and proceed — `evaluate.py` treats missing CIFs as "no candidate" for that composition. |
| Evaluate | **≤ 60 min** (fixed) | Scoring runs after train.py exits, as a separate `evaluate.py` subprocess (`num_workers=0`, `timeout=3600`). Not a campaign knob — `evaluate.py` is the fixed scorer. |

**`train_minutes` / `sample_minutes` are fixed per campaign (set at launch)
and uniform across all nodes; train.py must enforce them, and operators
(`draft` / `improve` / `debug`) must not raise them.**

### Required CLI + outputs

- CLI flags: `--max_minutes <float>` (training cap, default 120),
  `--sample_minutes <float>` (sampling cap, default 60), `--run_name <str>`.
- Training data: only `data/mp20_ps_train.pt`.
- Sampling: only `data/mp20_ps_val.pt`'s `atomic_numbers` field.
- CIF write path: `runs/<run_name>/val_samples/{idx:05d}.cif`.
- After CIFs written, invoke `python evaluate.py --samples_dir ...` as
  subprocess via `sys.executable`, with `timeout=3600`. On timeout,
  print `val_metre: nan` and exit cleanly.
- Single GPU only. The slot sets `CUDA_VISIBLE_DEVICES`; just use `cuda`.
- Self-contained at runtime: no pip install inside train.py.
- **No model checkpoints / no auxiliary file writes.** Forbid
  `torch.save(model.state_dict(), ...)`, EMA-save, optimizer-state-save,
  `lightning.save_checkpoint`, `model.save_pretrained`, etc. Only output:
  `runs/<run_name>/val_samples/*.cif`. No writes outside `runs/<run_name>/`.

### Required print at end

`train.py` MUST print `val_metre:` at the end (the harness parses it for the
tag). The `peak_vram_mb:` line is optional, informational (kept in `run.log`,
not parsed) — it lets a later `improve` judge VRAM headroom before scaling:

```
---
val_metre:        <float>
peak_vram_mb:     <float>     # informational
```

The parse step (`scripts/slot_parse.sh`) greps `^val_metre:` only. Operators
must not break that line prefix.
