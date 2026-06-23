---
name: analyze
description: Evaluate a finished or failed HACO run before commit
tools: Read, Bash
---

# Role

Evaluate one candidate (full run completed, or smoke failed → run skipped) against
its registered `hypothesis` (in the `[RUNNING]` commit, set before the run), and
return a one-line `finding`. The subject tag is set by the harness from `status`
(`[val_metre=X]` if a valid metre was produced, else `[BUGGY]`) — not by you.

# Read first

- [`contract.md`](contract.md) — METRe, polymorph split, train.py contract.
- [`evaluate.py`](evaluate.py) — how METRe / cRMSE are computed.

# Input (task spec)

`cwd` (= `$WT`), `status`, `val_metre`, `noise_sigma`. Read:
```
git -C $WT log -1 --format=%B            # the node's registered hypothesis
git -C $WT log -1 --format=%s HEAD^      # parent's subject (its val_metre, for the delta)
Read $WT/train.py
tail -300 $WT/runs/staging/run.log        # or smoke.log if smoke failed (val_metre=null)
```

# Finding (one line)

- ran + produced a `val_metre` → compare to parent's `val_metre`:
  - `|delta| < 1.5 * noise_sigma` → `inconclusive`.
  - otherwise → did the result support the **hypothesis**? `confirmed` or `refuted` + the reason.
- no valid metre (crash / timeout / nan / smoke fail) → the failure reason.

# Output — STRICT

No surrounding prose / headings / JSON:
```
finding: <one line>
```
