# HACO: Human–AI Co-discovery

**HACO** is a domain-agnostic AI co-scientist harness. Instead of fully
automating research, it *co-discovers* with a human expert: it searches methods
across fields, transfers a promising one into your task, and refines it under
sparse human guidance to find new algorithms.

Mechanically it is a **tree search over a git DAG of `train.py` variants** —
`draft` opens a new method branch, `improve` refines one, `debug` repairs a
crash — running indefinitely until interrupted. To steer it, a human drops a
`directives.md` under `runs/<run_tag>/`; each subagent reads it and applies what
fits its role, while the **orchestrator stays oblivious** — human guidance never
enters its context.

This repo is the **frozen, domain-agnostic template**. To apply it you author a
small set of task files (below); the harness then enforces a fair, sealed
evaluation around them by construction.

## How it works

- **Orchestrator** (`scripts/orchestrator.py`, deterministic) — the loop. It makes
  no research decisions and writes no code: it dispatches `select` for every
  choice, runs `scripts/slot_*.sh`, invokes subagents as `claude -p` subprocesses,
  and commits each result.
- **5 subagents** — `select` (route: next subagent + parent) · `draft` (pick a
  method, write `train.py`) · `improve` (one change) · `debug` (fix a crash) ·
  `analyze` (judge the run).
- **Memory = git** — every node is a commit under `agent/<run_tag>/*`; `git log`
  is the whole state. Heavy artifacts live in `runs/<run_tag>/<sha>/`.

## Apply to your task

On a fresh branch off `haco_v2`, run the **`/author-task`** skill. It writes the
task files (`task.md`, `prepare.py`, `metric.py`, `evaluate.py`,
`secret/reference.py`, `baselines.md`) for you. You supply only the three things
that *define* the task — they can't be inferred:

- **Data surface** — what `prepare.py` exposes to `train.py`.
- **Held-out reference** — the answer key, sealed in `secret/reference.py`.
- **Metric** — how output is scored against it; this is what every run optimizes.

```
/author-task <one-line goal>; dataset: <source>; reference: <ground-truth source>; metric: <how to score>
```

Per-file contracts and leakage rules live in the skill; the `train.py` contract
is in [`contract.md`](contract.md). `scripts/validate_task.sh` is the fail-closed
gate — it refuses to start if the public surface can reach `secret/`.

> `train.py` is the only editable file. Everything else — the orchestrator,
> subagents, and slot plumbing under `scripts/` — is frozen core; don't edit it
> per task.

## Run

**1. Bootstrap** (human, clean tree required) — validates the split, builds the
base venv, prepares public data + sealed held-out, detects hardware, writes
`campaign.json`:

```
git checkout <task-branch>
scripts/bootstrap.sh run_tag=<run_tag> [gpus=all] [wall_minutes=<override>] [cpu_threads=<override>]
```

Only `run_tag` is required. `gpus` defaults to all detected; `wall_minutes`
defaults to `task.md`'s frontmatter; `cpu_threads` caps per-run threads
(default `nproc / n_slots`) — set it only when campaigns share a host.

**2. Launch** — the deterministic driver, in tmux (needs `claude` on PATH; runs
until interrupted, restart-safe — re-running reconciles in-flight slots):

```
python3 scripts/orchestrator.py <run_tag>
```

## Learn more

- [`contract.md`](contract.md) — the `train.py` contract every subagent obeys.
- `/author-task` skill — the full task-authoring recipe.

## License

MIT (see [LICENSE](LICENSE)).
