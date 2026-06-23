# HACO — orchestrator loop

The git commit DAG under `agent/<run_tag>/*` is the search graph **and** the
memory; `git log` is the only state store. The orchestrator **decides** (operator, parent)
and **executes** by calling `scripts/*.sh` and dispatching the 6
subagents. The orchestrator never authors code, never runs WebSearch, never improvises bash.

## Startup

`runs/<run_tag>/campaign.json` holds `run_tag`, `gpus`, `n_slots`, `vram_total_mb`, `train_minutes`,
`sample_minutes`, `smoke_seconds` — the durable source of truth. Start by reading
it (`run_tag` from the launch prompt); re-read on every dispatch and on recovery;
never parse config from the prompt. Then Initial launch.

## Hard rules

- Dispatch only the 6 subagents: `idea` `draft` `improve` `debug` `smoke` `analyze`.
- A `SubagentStop` hook signals every subagent completion into `.slots/events.log` — keep a `Monitor` on it (any line) from the start and reconcile from files on each wake, never blocking on background-agent notifications.
- Run `train.py` only via `scripts/slot_run.sh` (`smoke` runs train.py inside its own subagent).
- No same-cycle retry after a smoke fail / crash: the slot goes idle; the next attempt is a fresh cycle from a new worktree (the `[BUGGY]` tip becomes its `target_sha`).
- `debug` and `improve` keep the target/parent's pair (paradigm + architecture); only `draft` establishes a new pair.
- Decisions use only run-scoped `git log` + commit bodies + `run.log`; never read another run's branches (no `--all`).

## Reading the tree (selection)

```
git log --branches='agent/<run_tag>/*' --format='%h %s%n%b'      # committed + [RUNNING], one query
```

Subject tag = status: `[val_metre=X]` ok · `[BUGGY]` invalid · `[RUNNING]` in
progress (placeholder, never a selection target). Body carries `pair:`,
`parent:`, `hypothesis:`, `finding:`. node = commit, op = subject prefix.

Pick operator + parent/target by judgment:
- no useful node yet / want a new paradigm → **draft** route: dispatch `idea` first for the pair, then `draft` (the orchestrator never picks the pair).
- build on a `[val_metre]` node → **improve**.
- a `[BUGGY]` leaf that looks fixable (read its `finding`) → **debug**.
- read each node's `finding` (hypothesis confirmed/refuted/inconclusive).
- **Exploration floor**: keep the `draft` node count ≥ `improve` node count / 3; while violated, idle slots go to `idea`+`draft`.

## Notation

- `$N` slot index `0..n_slots-1` → worktree `$WT=.worktrees/slot-$N`, physical GPU `$GPU=gpus[$N]`.
- `$PY=$WT/runs/staging/.venv/bin/python` · `$BRANCH=agent/<run_tag>/n<i>-<op>`.
- `parent_ref` = `<parent_sha>` (improve/debug) | `agent/root` (draft).
- Slot busy ⟺ `$WT` exists; idle ⟺ it does not.

## Per-slot pipeline

1. **Decide** operator + parent/target. For draft, dispatch `idea` first and take the pair from its reply.
2. **Setup**
   ```
   mkdir -p .slots
   printf '%s' "<pair>" > .slots/slot-$N.pair       # draft: from idea; improve/debug: parent's `pair:`
   scripts/slot_setup.sh $N <parent_ref> $BRANCH <run_tag> <op> .slots/slot-$N.pair [<parent_sha>]
   ```
3. **Operator** — `Agent(<op>, <task spec>)`. Multiple idle slots → one message, parallel calls.
4. **Verify + register hypothesis** — `[ -s $WT/train.py ]` (else treat as buggy → step 9). Write the operator's returned `hypothesis` to its slot file, then register it in the `[RUNNING]` commit (before the run):
   ```
   printf '%s' "<hypothesis from the operator reply>" > .slots/slot-$N.hypothesis
   scripts/slot_register.sh $N
   ```
5. **Smoke** — `Agent(smoke, <task spec>)`:
   - `pass` → `rm -rf $WT/runs/staging-smoke`, go to 6.
   - `fail` → `scripts/slot_parse.sh $N <run_tag> --smoke`, skip to 8.
6. **Run** — `scripts/slot_run.sh $N $GPU $PY <run_tag> <train_minutes> <sample_minutes>` (backgrounds, returns; appends `slot=$N exit=$?` to `.slots/events.log`).
7. **Parse** (on event `slot=$N exit=<code>`) — `scripts/slot_parse.sh $N <run_tag> <code>` → `runs/staging/parsed.env`.
8. **Analyze** — `Agent(analyze, <task spec>)` → `finding`. Write `printf '%s' "<finding>" > .slots/slot-$N.finding`.
9. **Finalize**
   ```
   scripts/slot_finalize.sh $N <run_tag> <op> [<parent_sha>]
   ```
   slot idle. Dispatch the next candidate (step 1).

## Task specs

- **idea** — `{run_tag, n_pairs}`. Returns N pairs (paradigm + architecture, each with `refs:`).
- **draft** — `run_tag`, `pair` (from idea, carries `refs:`), `cwd`, `python`.
- **improve** — `run_tag`, `parent_sha`, `cwd`, `python`.
- **debug** — `run_tag`, `target_sha`, `cwd`, `python`.
- **smoke** — `gpu`, `vram_total_mb`, `smoke_seconds`, `python`, `cwd`.
- **analyze** — `cwd`, `status`, `val_metre`, `noise_sigma`.

## Initial launch

`idea {run_tag, n_pairs:<#idle slots>}` → per slot: step 2 (setup) → step 3
(`draft`, all slots in one parallel message) → step 4 → step 5 (`smoke`,
parallel) → pass: step 6; fail: steps 7–9. Then start `Monitor` on
`.slots/events.log`.

## Event loop

Per line `slot=$N exit=<code>` from `Monitor`: steps 7 → 8 → 9 → re-read `program.md` → step 1 (next
candidate for slot N). Runs indefinitely; never stop unless interrupted.

## Recovery (on restart)

Read back `runs/<run_tag>/campaign.json`, then `scripts/slot_reconcile.sh
<run_tag> <n_slots>`. Running slots keep their live event; the rest end idle.
