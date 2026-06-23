#!/usr/bin/env bash
# Step 6: amend the [RUNNING] placeholder into the final node, move runs, remove the
# worktree. Idempotent. Body = method / parent (improve/debug) / hypothesis / finding,
# from runs/staging/ + the [RUNNING] body. Tag from score: a number → [score=X], else [BUGGY].
# Usage: slot_finalize.sh <N> <run_tag> <prefix> [parent_sha]   prefix: draft|improve|debug
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Same shared-.git flock as slot_add.sh (freeze already ran, outside this lock).
exec {LOCKFD}>"$(git rev-parse --git-common-dir)/haco-campaign.lock"
flock "$LOCKFD"

N="$1"; run_tag="$2"; prefix="$3"; parent_sha="${4:-}"
WT=".worktrees/slot-${N}"
repo="$PWD"
staging="$WT/runs/staging"

# Idempotency: worktree already removed → already finalized.
if [ ! -d "$WT" ]; then
  echo "slot_finalize: slot=${N} already finalized (no worktree)"; exit 0
fi

# runs/staging/ holds this cycle's transient metadata (cat → free text is safe).
score="$(cat "$staging/score" 2>/dev/null || true)"

# Amend only while still the [RUNNING] placeholder (re-run safe; cleanup below is idempotent).
subject="$(git -C "$WT" log -1 --format='%s')"
if [[ "$subject" == *"[RUNNING]"* ]]; then
  # draft's method is in runs/staging/method; improve/debug have it in the [RUNNING]
  # body. Strip a leading label the agent may have written (re-added below).
  if [ "$prefix" = "draft" ]; then
    method="$(cat "$staging/method" 2>/dev/null | sed 's/^method:[[:space:]]*//' || true)"
  else
    method="$(git -C "$WT" log -1 --format=%b | sed -n 's/^method: //p')"
  fi
  hypothesis="$(cat "$staging/hypothesis" 2>/dev/null | sed 's/^hypothesis:[[:space:]]*//' || true)"
  finding="$(cat "$staging/finding" 2>/dev/null | sed 's/^finding:[[:space:]]*//' || true)"
  # Tag from score alone: a number → [score=X]; nan/empty/non-numeric → [BUGGY].
  if printf '%s' "$score" | grep -Eq '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$'; then
    tag="[score=${score}]"
  else
    tag="[BUGGY]"
  fi
  args=(-m "${prefix}: ${tag}" -m "method: ${method}")
  [ "$prefix" != "draft" ] && [ -n "$parent_sha" ] && args+=(-m "parent: ${parent_sha}")
  [ -n "$hypothesis" ] && args+=(-m "hypothesis: ${hypothesis}")
  [ -n "$finding" ]    && args+=(-m "finding: ${finding}")
  git -C "$WT" add train.py baselines.md 2>/dev/null || true
  # --allow-empty: the [RUNNING] placeholder is empty; a buggy node may add no files.
  git -C "$WT" commit --amend --allow-empty "${args[@]}"
else
  echo "slot_finalize: slot=${N} already amended; completing cleanup only"
fi

sha="$(git -C "$WT" rev-parse --short HEAD)"
mkdir -p "$repo/runs/${run_tag}"
# freeze already ran (slot_freeze.sh, before the lock). mv carries staging metadata
# + artifacts into the permanent node dir; worktree removal drops the transient copy.
[ -d "$staging" ] && mv "$staging" "$repo/runs/${run_tag}/${sha}"
git worktree remove --force "$WT"

echo "slot_finalize ok: slot=${N} sha=${sha} tag=${tag:-(cleanup)}"
