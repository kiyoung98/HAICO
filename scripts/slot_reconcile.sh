#!/usr/bin/env bash
# Recovery: reconcile each slot against reality. Worktree with a live train.py is
# still running; one without is a stalled attempt → clean it up.
# Usage: slot_reconcile.sh <run_tag> <n_slots>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Same shared-.git flock as slot_add.sh: worktree remove + branch -D below must not
# race a co-tenant campaign's worktree add. Startup-only, so held for the whole loop.
exec {LOCKFD}>"$(git rev-parse --git-common-dir)/haco-campaign.lock"
flock "$LOCKFD"

run_tag="$1"; n_slots="$2"

for ((N=0; N<n_slots; N++)); do
  WT=".worktrees/slot-${N}"
  if [ ! -d "$WT" ]; then
    echo "slot=${N} idle"
    continue
  fi
  # Absolute worktree path: co-tenant campaigns share one .git, so a relative pattern
  # would match the other campaign's slot-N train.
  if pgrep -f "${PWD}/${WT}/.*train.py" >/dev/null 2>&1; then
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
