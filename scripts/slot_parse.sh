#!/usr/bin/env bash
# Steps 5(fail)+7: parse the run result, or consolidate smoke-fail artifacts.
# Writes runs/staging/parsed.env with status + val_metre only (resources/trace stay
# in run.log).
# Usage: slot_parse.sh <N> <run_tag> <exit_code>     # after a full run
#        slot_parse.sh <N> <run_tag> --smoke          # after a smoke fail
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

N="$1"; run_tag="$2"; mode="$3"     # run_tag kept for call symmetry
WT=".worktrees/slot-${N}"
staging="$WT/runs/staging"
val_metre=""; status=""

if [ "$mode" = "--smoke" ]; then
  [ -f "$WT/runs/staging-smoke/smoke.log" ] && mv "$WT/runs/staging-smoke/smoke.log" "$staging/"
  [ -d "$WT/runs/staging-smoke/val_samples" ] && mv "$WT/runs/staging-smoke/val_samples" "$staging/smoke_val_samples"
  rmdir "$WT/runs/staging-smoke" 2>/dev/null || true
  status="crash"
else
  exit_code="$mode"
  val_metre="$(grep '^val_metre:' "$staging/run.log" 2>/dev/null | tail -1 | awk '{print $2}' || true)"
  if [ "$exit_code" = "0" ] && [ -n "$val_metre" ] && [ "$val_metre" != "nan" ]; then
    status="ok"
  else
    status="crash"
  fi
fi

cat > "$staging/parsed.env" <<ENV
status=${status}
val_metre=${val_metre}
ENV

echo "slot_parse ok: slot=${N} status=${status} val_metre=${val_metre:-}"
