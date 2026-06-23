#!/usr/bin/env bash
# Step 4: register the operator's hypothesis into the [RUNNING] commit, before the
# run. Reads .slots/slot-<N>.hypothesis (main wrote it from the operator's reply)
# and appends it as a `hypothesis:` trailer. Idempotent: only while still
# [RUNNING] and only if no hypothesis is present yet.
# Usage: slot_register.sh <N>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

N="$1"
WT=".worktrees/slot-${N}"
hyp_file=".slots/slot-${N}.hypothesis"

[ -f "$hyp_file" ] || { echo "slot_register: slot=${N} no hypothesis file; skip"; exit 0; }

body="$(git -C "$WT" log -1 --format='%B')"
case "$body" in
  *"[RUNNING]"*) ;;                                                       # only while [RUNNING]
  *) echo "slot_register: slot=${N} not [RUNNING]; skip"; exit 0 ;;
esac
if printf '%s\n' "$body" | grep -q '^hypothesis:'; then
  echo "slot_register: slot=${N} already has hypothesis; skip"; exit 0
fi

# Re-pass the whole existing message as one -m, then append the hypothesis trailer.
git -C "$WT" commit --amend --allow-empty \
  -m "$body" \
  -m "hypothesis: $(cat "$hyp_file")"
echo "slot_register ok: slot=${N}"
