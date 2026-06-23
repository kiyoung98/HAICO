#!/usr/bin/env bash
# Step 4: launch the full run detached (setsid) with an OS timeout. The tail folds in
# scoring, writes the score, then the exit marker — result on disk before the event.
# Usage: slot_run.sh <N> <gpu> <python> <run_tag> <wall_minutes> [cpu_threads]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

N="$1"; gpu="$2"; py="$3"; run_tag="$4"; wall_minutes="$5"; cpu_threads="${6:-0}"
WT=".worktrees/slot-${N}"
repo="$PWD"

[ -s "$WT/train.py" ] || { echo "slot_run: $WT/train.py missing/empty" >&2; exit 1; }

os_timeout=$(( (wall_minutes + 90) * 60 ))

# train.py runs in cwd=$WT (sealed, network off); the scorer appends `score:` to
# run.log, the tail greps it into runs/staging/score. A non-zero train.py exit forces
# nan (a crash can't be salvaged by a stale score). Recorded exit is train.py's.
no_net="http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 no_proxy=localhost,127.0.0.1"
# Per-run CPU thread cap: bound OMP/BLAS pools so one run can't starve its siblings
# (runs are wall-clock-capped). 0/unset → no cap.
thread_env=""
if [ "${cpu_threads}" -gt 0 ] 2>/dev/null; then
  thread_env="OMP_NUM_THREADS=${cpu_threads} OPENBLAS_NUM_THREADS=${cpu_threads} MKL_NUM_THREADS=${cpu_threads} NUMEXPR_NUM_THREADS=${cpu_threads} VECLIB_MAXIMUM_THREADS=${cpu_threads}"
fi
setsid bash -c "cd '${repo}/${WT}'; CUDA_VISIBLE_DEVICES='${gpu}' ${no_net} ${thread_env} timeout ${os_timeout} '${repo}/${py}' train.py --max_minutes ${wall_minutes} --run_name staging > runs/staging/run.log 2>&1; tc=\$?; '${repo}/scripts/slot_score.sh' '${N}' '${repo}/${py}' '${run_tag}' staging >> runs/staging/run.log 2>&1 || true; sc=\$(grep '^score:' runs/staging/run.log | tail -1 | awk '{print \$2}'); [ \"\$tc\" = 0 ] || sc=nan; printf '%s\\n' \"\${sc:-nan}\" > runs/staging/score; echo \"slot=${N} exit=\${tc}\" >> '${repo}/events.log'" >/dev/null 2>&1 &

echo "slot_run launched: slot=${N} gpu=${gpu} os_timeout=${os_timeout}s cpu_threads=${cpu_threads}"
