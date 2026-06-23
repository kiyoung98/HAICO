#!/usr/bin/env bash
# Recovery: reconcile each slot's declared state against reality. A worktree with
# a live train.py is still running; one without is a stalled attempt → clean it
# up (the [RUNNING] tip never finished, so there is no result to keep).
# Usage: slot_reconcile.sh <run_tag> <n_slots>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

run_tag="$1"; n_slots="$2"

for ((N=0; N<n_slots; N++)); do
  WT=".worktrees/slot-${N}"
  if [ ! -d "$WT" ]; then
    echo "slot=${N} idle"
    continue
  fi
  if pgrep -f "${WT}.*train.py" >/dev/null 2>&1; then
    echo "slot=${N} running (live train.py) — leave it"
  else
    branch="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git worktree remove --force "$WT"
    if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
      git branch -D "$branch" 2>/dev/null || true
    fi
    echo "slot=${N} stalled → cleaned (now idle)"
  fi
done
