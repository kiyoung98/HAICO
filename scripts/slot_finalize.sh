#!/usr/bin/env bash
# Step 9+10: amend the [RUNNING] placeholder into the final node, move runs, and
# remove the worktree. Idempotent (re-run on a finalized slot = no-op).
# Body = pair / (parent for improve/debug) / hypothesis / finding. pair + hypothesis
# are already in the [RUNNING] body (registered at Step 2 / Step 4); finding comes
# from .slots/slot-<N>.finding.
# Usage: slot_finalize.sh <N> <run_tag> <prefix> [parent_sha]
#   prefix  : draft | improve | debug
# Tag is deterministic from status (parsed.env): a valid val_metre → [val_metre=X], else [BUGGY].
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"

N="$1"; run_tag="$2"; prefix="$3"; parent_sha="${4:-}"
WT=".worktrees/slot-${N}"
repo="$PWD"
staging="$WT/runs/staging"

# Idempotency: worktree already removed → already finalized.
if [ ! -d "$WT" ]; then
  echo "slot_finalize: slot=${N} already finalized (no worktree)"; exit 0
fi

status=""; val_metre=""
# shellcheck disable=SC1090,SC1091
[ -f "$staging/parsed.env" ] && . "$staging/parsed.env"

# Amend only while still the [RUNNING] placeholder (re-run safe; cleanup below is idempotent).
subject="$(git -C "$WT" log -1 --format='%s')"
if [[ "$subject" == *"[RUNNING]"* ]]; then
  body="$(git -C "$WT" log -1 --format='%B')"
  pair="$(printf '%s\n' "$body" | sed -n 's/^pair: //p' | head -1)"
  hypothesis="$(printf '%s\n' "$body" | sed -n 's/^hypothesis: //p' | head -1)"
  finding="$(cat ".slots/slot-${N}.finding" 2>/dev/null || true)"
  if [ "$status" = "ok" ]; then
    tag="[val_metre=${val_metre}]"
  else
    tag="[BUGGY]"
  fi
  args=(-m "${prefix}: ${tag}" -m "pair: ${pair}")
  [ "$prefix" != "draft" ] && [ -n "$parent_sha" ] && args+=(-m "parent: ${parent_sha}")
  [ -n "$hypothesis" ] && args+=(-m "hypothesis: ${hypothesis}")
  [ -n "$finding" ]    && args+=(-m "finding: ${finding}")
  git -C "$WT" add train.py 2>/dev/null || true
  # --allow-empty: the [RUNNING] placeholder is an empty commit; a buggy node may
  # carry no file changes, and amend must still succeed.
  git -C "$WT" commit --amend --allow-empty "${args[@]}"
else
  echo "slot_finalize: slot=${N} already amended; completing cleanup only"
fi

sha="$(git -C "$WT" rev-parse --short HEAD)"
mkdir -p "$repo/runs/${run_tag}"
# Freeze this node's exact env so children reconstruct it from cache (hardlinks),
# never a full copy. Written into staging so the existing mv carries it to the
# permanent node dir; mv preserves the cache hardlinks.
if [ -d "$staging/.venv" ]; then
  VIRTUAL_ENV="$staging/.venv" "$UV" pip freeze > "$staging/requirements.lock"
fi
[ -d "$staging" ] && mv "$staging" "$repo/runs/${run_tag}/${sha}"
git worktree remove --force "$WT"

echo "slot_finalize ok: slot=${N} sha=${sha} tag=${tag:-(cleanup)}"
