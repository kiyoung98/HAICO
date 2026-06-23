#!/usr/bin/env bash
# Step 2a (locked): create the slot worktree on its branch + write the [RUNNING]
# placeholder commit — the fast shared-.git ops, split from the slow venv build so
# GIT_LOCK covers only these. The tip is [RUNNING] the instant it exists, so a crash
# before slot_setup never leaves a tip at the parent node. improve/debug seal
# method+parent in the body; draft's method arrives at finalize.
# Usage: slot_add.sh <N> <parent_ref> <branch> <op> [parent_sha]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# GIT_LOCK is process-local; flock the shared .git so co-tenant campaigns don't
# race worktree add/remove on packed-refs. Held to script exit (covers the trap).
exec {LOCKFD}>"$(git rev-parse --git-common-dir)/haco-campaign.lock"
flock "$LOCKFD"

N="$1"; parent_ref="$2"; branch="$3"; op="$4"; parent_sha="${5:-}"
WT=".worktrees/slot-${N}"

# Trailing slash anchors the slot dir (else slot-1 matches slot-10/11/...).
pkill -f "${PWD}/${WT}/.*train\.py" 2>/dev/null || true
git worktree add -b "$branch" "$WT" "$parent_ref"

# Roll back the worktree+branch on any failure below, so recovery never finds a
# half-made node. Cleared on success.
trap 'rc=$?; [ "$rc" -ne 0 ] && { git worktree remove --force "$WT" 2>/dev/null || true; git branch -D "$branch" 2>/dev/null || true; }' EXIT

# method read from the parent commit body (never an arg → no shell re-eval).
msg_args=(-m "${op}: [RUNNING]")
if [ "$op" != "draft" ] && [ -n "$parent_sha" ]; then
  method="$(git log -1 --format=%b "$parent_sha" | sed -n 's/^method: //p')"
  msg_args+=(-m "method: ${method}" -m "parent: ${parent_sha}")
fi
git -C "$WT" commit --allow-empty "${msg_args[@]}"

trap - EXIT
echo "slot_add ok: slot=${N} branch=${branch}"
