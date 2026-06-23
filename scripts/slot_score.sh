#!/usr/bin/env bash
# Sealed scoring: run evaluate.py from the MAIN repo (holds secret/) against the
# worktree artifact, print `score:`. train.py never does this.
# Usage: slot_score.sh <slot_idx> <python> <run_tag> <run_name>
set -euo pipefail
# Main repo root from script location (worktree cwd would find the wrong evaluate.py).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

N="${1:?slot idx}"; PY="${2:?python}"; run_tag="${3:?run_tag}"; run_name="${4:?run_name}"
artifact_dir=".worktrees/slot-${N}/runs/${run_name}"
[ -d "$artifact_dir" ] || { echo "slot_score: missing ${artifact_dir}" >&2; echo "score: nan"; exit 0; }

timeout 3600 "$PY" "${ROOT}/evaluate.py" --run_dir "$artifact_dir" \
  || { echo "slot_score: evaluate.py failed or timed out" >&2; echo "score: nan"; }
