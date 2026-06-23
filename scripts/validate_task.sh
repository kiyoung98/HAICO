#!/usr/bin/env bash
# Fail-closed authoring gate: a solver-view file must never reach the held-out.
# Checks: required files + secret/ exist; prepare.py/metric.py/task.md/baselines.md
# don't name secret/ or import the reference; metric.py is path-free (pure).
# Usage: validate_task.sh [task_root]
set -euo pipefail
root="${1:-.}"
cd "$root"

fail() { echo "validate: FAIL -- $*" >&2; exit 1; }
SOLVER_VIEW=(prepare.py metric.py task.md baselines.md)

# --- 1. required files / dirs ---
for f in prepare.py metric.py evaluate.py task.md baselines.md requirements.txt; do
  [ -f "$f" ] || fail "missing required file: $f"
done
[ -d secret ] || fail "missing held-out dir: secret/ (the ground truth must live here)"
ls secret/*.py >/dev/null 2>&1 || fail "secret/ has no loader (.py) -- where is reference() ?"

# --- 2. solver-view files must not reach the held-out ---
for f in "${SOLVER_VIEW[@]}"; do
  if grep -nE '(^|[^A-Za-z_])secret[/.]' "$f" >/dev/null 2>&1; then
    fail "$f references secret/ -- solver-view files must not reach the held-out"
  fi
  if grep -nE 'import[[:space:]].*reference|from[[:space:]].*reference' "$f" >/dev/null 2>&1; then
    fail "$f imports the reference module -- the held-out accessor must not be in the solver view"
  fi
done

# --- 3. metric.py must be path-free (pure function over (output, reference)) ---
if grep -nE 'torch\.load|np\.load|[^a-z]open\(|urllib|requests\.|\.lmdb|/data/|"data/|\x27data/' metric.py >/dev/null 2>&1; then
  fail "metric.py loads data -- it must be a pure score(output, reference); the loader belongs in secret/ + evaluate.py"
fi

echo "validate: OK -- public surface is clean; held-out confined to secret/ (task root: $root)"
