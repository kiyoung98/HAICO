#!/usr/bin/env bash
# Steps 4+6: verify the operator's writes, then launch the full run in the
# background with an OS-level timeout and an exit-marker writer. Returns
# immediately; the run is detached (setsid) and survives this call.
# Usage: slot_run.sh <N> <gpu> <python> <run_tag> <train_minutes> <sample_minutes>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

N="$1"; gpu="$2"; py="$3"; run_tag="$4"; train_minutes="$5"; sample_minutes="$6"
WT=".worktrees/slot-${N}"
repo="$PWD"

[ -s "$WT/train.py" ] || { echo "slot_run: $WT/train.py missing/empty" >&2; exit 1; }

os_timeout=$(( (train_minutes + sample_minutes + 90) * 60 ))
mkdir -p "$repo/.slots"

# All interpolated values are controlled (ints / venv paths), never free text.
setsid bash -c "CUDA_VISIBLE_DEVICES='${gpu}' timeout ${os_timeout} '${py}' '${WT}/train.py' --max_minutes ${train_minutes} --sample_minutes ${sample_minutes} --run_name staging > '${WT}/runs/staging/run.log' 2>&1; echo \"slot=${N} exit=\$?\" >> '${repo}/.slots/events.log'" >/dev/null 2>&1 &

echo "slot_run launched: slot=${N} gpu=${gpu} os_timeout=${os_timeout}s"
